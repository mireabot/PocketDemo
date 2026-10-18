import Dependencies
import Domain
import Foundation
import GRDB
import PocketNetworking
@testable import PocketSync

struct VerificationFailure: Error, CustomStringConvertible { let description: String }
func check(_ condition: Bool, _ message: String) throws {
    guard condition else { throw VerificationFailure(description: message) }
    print("PASS \(message)")
}

func sample(_ id: String = "sample", version: Int64 = 10, title: String = "Server title", summary: String = "Server summary") -> Recording {
    Recording(id: RecordingID(id), title: title, summary: summary, version: version, createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 1), updatedBy: nil, segmentCount: 1)
}

func rows(_ db: Database) throws -> [RecordingRow] {
    try RecordingRecord.visible.order(RecordingRecord.Columns.createdAt.desc, RecordingRecord.Columns.id).fetchAll(db).map { try $0.row(in: db) }
}

struct SyncFixture: Sendable {
    let database: PocketDB
    let supervisor: Supervisor
    let repository: RecordingsRepository

    init(path: URL, serverURL: URL, pageSize: Int = 17) throws {
        let database = try PocketDB.open(path)
        self.database = database
        let deviceID = try database.reader.read { try SyncStateRecord.load(in: $0).deviceID }
        let client = RestClient(.init(baseURL: serverURL, adapters: [StaticHeaders(["X-Device-Id": deviceID])]))
        let supervisor = Supervisor(database: database, client: client, pageSize: pageSize)
        self.supervisor = supervisor
        repository = withDependencies {
            $0.pocketDB = database
            $0.supervisor = supervisor
        } operation: { RecordingsRepository() }
    }

    func edit(_ id: RecordingID, set changes: [EditableField: String]) async throws {
        guard let detail = try await database.reader.read({ try RecordingRecord.detail(id, in: $0) }) else { throw VerificationFailure(description: "Missing recording for edit") }
        var draft = RecordingDraft(detail)
        if let title = changes[.title] { draft.title = title }
        if let summary = changes[.summary] { draft.summary = summary }
        try await repository.save(draft)
    }
}

@main
struct VerifySync {
    static func main() async throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        try await NetworkingChecks.run()
        try databaseScenarios()
        try await defaultPaginationScenario()
        try await backendScenarios()
        try await RecoveryChecks.run()
        print("All iOS checks passed.")
    }

    static func databaseScenarios() throws {
        let database = try PocketDB.open(nil)
        let id = RecordingID("sample")
        try database.writer.write { db in
            try RecordingRecord.accept(sample(), in: db)
            try MutationRecord.edit(id, field: .title, value: "First local title", in: db)
            try MutationRecord.edit(id, field: .title, value: "Second local title", in: db)
            let mutations = try MutationRecord.live(id, in: db)
            try check(mutations.count == 2, "each edit has a mutations row")
            try check(rows(db).first?.title == "Second local title", "pending edits appear in the observed domain model")
            try check(RecordingRecord.fetchOne(db, key: id.rawValue)?.title == "Server title", "editing preserves server baseline")
            try check(mutations[1].oldValue == "Server title", "merge base comes from server snapshot")
            let first = mutations[0]
            _ = try MutationRecord.claim(in: db)
            try check(MutationRecord.next(in: db)?.id == first.id, "inflight request keeps exact mutation id")
            try MutationRecord.acknowledge(first, server: sample(version: 11, title: "First local title"), in: db)
            try check(rows(db).first?.title == "Second local title", "acknowledgment preserves later edits")
            try RecordingRecord.accept(sample(version: 9, title: "Old replay"), in: db)
            try check(RecordingRecord.fetchOne(db, key: id.rawValue)?.version == 11, "old replay cannot overwrite newer baseline")
            guard let second = try MutationRecord.next(in: db) else { throw VerificationFailure(description: "Missing next edit") }
            _ = try MutationRecord.recordConflict(second, current: sample(version: 12, title: "Their title"), fields: [.title], changedBy: "other-device", changedAt: Date(), mayRebase: true, in: db)
            do {
                try MutationRecord.delete(id, in: db)
                throw VerificationFailure(description: "Delete should require conflict resolution")
            } catch IntentError.conflictNeedsResolution {}
            try check(rows(db).first?.sync == .needsResolution, "known conflict stays reachable on attempted deletion")
            guard case let .field(conflict) = try RecordingRecord.detail(id, in: db)?.conflicts.first else { throw VerificationFailure(description: "Missing conflict") }
            try MutationRecord.resolve(conflict, with: .keepMine, in: db)
            try check(MutationRecord.next(in: db)?.baseVersion == 12, "keep mine uses latest server version")
            try TranscriptRecord.store(id, segments: [.init(id: 0, startMs: 0, text: "Old transcript")], in: db)
            try RecordingRecord.accept(sample("cache-only"), in: db)
            try SyncStateRecord.beginReset(in: db)
            let reset = try SyncStateRecord.load(in: db)
            try check(RecordingRecord.fetchOne(db, key: "cache-only") == nil, "reset drops recordings without local work")
            try check(SyncStateRecord.unrefreshed(in: db) == [id], "reset keeps a recording with local work for a refresh")
            try check(TranscriptRecord.wanted.fetchCount(db) == 1, "reset keeps the transcript request of a kept recording")
            try RecordingRecord.accept(sample(version: 1, title: "New epoch"), generation: reset.generation, reset: true, in: db)
            try check(RecordingRecord.fetchOne(db, key: id.rawValue)?.title == "New epoch", "reset accepts lower server versions")
            try SyncStateRecord.endReset(in: db)
            try check(MutationRecord.next(in: db)?.baseVersion == 1, "reset rebases surviving mutations")
            try check(rows(db).first?.title == "Second local title", "reset preserves local title")
            try RecordingRecord.remove(id, in: db)
            try check(rows(db).isEmpty, "remote removal removes displayed recording")
            try check(MutationRecord.fetchCount(db) == 0, "remote removal removes affected mutations")
            try check(NoticeRecord.fetchCount(db) == 1, "remote removal leaves notice for lost edits")
        }
        try restoringOriginalValueScenario()
        try transcriptCacheScenario()
        try conflictAndDraftScenarios()
        let path = URL.temporaryDirectory.appending(path: "pocket-reopen-\(UUID().uuidString).sqlite")
        defer { removeDatabase(path) }
        let mutationID: String
        do {
            let disk = try PocketDB.open(path)
            mutationID = try disk.writer.write { db in
                try RecordingRecord.accept(sample(), in: db)
                try MutationRecord.edit(id, field: .summary, value: "Saved before quit", in: db)
                guard let mutation = try MutationRecord.claim(in: db) else { throw VerificationFailure(description: "Missing disk mutation") }
                return mutation.id
            }
        }
        let reopened = try PocketDB.open(path)
        try reopened.reader.read { db in
            try check(MutationRecord.next(in: db)?.id == mutationID, "inflight identity survives reopening SQLite")
            try check(rows(db).first?.summary == "Saved before quit", "reopened DB displays unsynced edit")
        }
    }

    static func transcriptCacheScenario() throws {
        let database = try PocketDB.open(nil)
        let segments = [Transcript.Segment(id: 0, startMs: 0, text: String(repeating: "word ", count: 200))]
        let size = try JSONEncoder().encode(segments).count
        try database.writer.write { db in
            for name in ["a", "b", "c"] {
                try RecordingRecord.accept(sample(name), in: db)
                try TranscriptRecord.request(RecordingID(name), in: db)
            }
            try TranscriptRecord.store(RecordingID("a"), segments: segments, limit: size * 2, in: db)
            try TranscriptRecord.store(RecordingID("b"), segments: segments, limit: size * 2, in: db)
            try db.execute(sql: "UPDATE transcripts SET opened_at = ? WHERE recording_id = 'b'", arguments: [Date(timeIntervalSince1970: 1)])
            try TranscriptRecord.request(RecordingID("a"), in: db)
            try TranscriptRecord.store(RecordingID("c"), segments: segments, limit: size * 2, in: db)
            let cached = try TranscriptRecord.filter(TranscriptRecord.Columns.state == "cached").fetchAll(db).map(\.recordingID).sorted()
            try check(cached == ["a", "c"], "transcript cache over its limit evicts the least recently opened transcript")
            try check(TranscriptRecord.cacheLimitBytes == 30 * 1024 * 1024, "transcript cache limit defaults to 30 MB")
            try TranscriptRecord.request(RecordingID("b"), in: db)
            try check(TranscriptRecord.wanted.fetchAll(db).map(\.recordingID) == ["b"], "reopening an evicted recording requests its transcript again")
        }
    }

    static func restoringOriginalValueScenario() throws {
        let database = try PocketDB.open(nil)
        let id = RecordingID("sample")
        try database.writer.write { db in
            try RecordingRecord.accept(sample(), in: db)
            try MutationRecord.edit(id, field: .title, value: "Temporary local title", in: db)
            try MutationRecord.edit(id, field: .title, value: "Server title", in: db)
            try check(RecordingRecord.detail(id, in: db)?.title == "Server title", "offline edit can restore the server title")
            try check(MutationRecord.live(id, in: db).count == 2, "restoring the title queues a second edit")
        }
    }

    static func conflictAndDraftScenarios() throws {
        let database = try PocketDB.open(nil)
        let id = RecordingID("sample")
        try database.writer.write { db in
            try RecordingRecord.accept(sample(), in: db)
            guard let original = try RecordingRecord.detail(id, in: db) else { throw VerificationFailure(description: "Missing initial detail") }
            var draft = RecordingDraft(original)
            draft.title = "Edited in form"
            try RecordingRecord.accept(sample(version: 11, summary: "Server summary arrived during edit"), in: db)
            try check(draft.changes == [.title: "Edited in form"], "draft submits only fields the user changed")
            for (field, value) in draft.changes {
                try MutationRecord.edit(id, field: field, value: value, basedOn: draft.original.base, in: db)
            }
            try check(rows(db).first?.summary == "Server summary arrived during edit", "saving title preserves newer untouched summary")
            try check(MutationRecord.next(in: db)?.baseVersion == 10, "draft retains server revision shown when opened")
            try MutationRecord.edit(id, field: .title, value: "Latest local title", in: db)
            try MutationRecord.delete(id, in: db)
            try check(rows(db).isEmpty, "queued delete hides unconflicted recording")
            guard let first = try MutationRecord.claim(in: db) else { throw VerificationFailure(description: "Missing queued edit") }
            _ = try MutationRecord.recordConflict(first, current: sample(version: 12, title: "Remote title"), fields: [.title], changedBy: "other-device", changedAt: Date(), mayRebase: true, in: db)
            try check(rows(db).first?.sync == .needsResolution, "newly discovered conflict unhides blocked delete")
            guard case let .field(conflict) = try RecordingRecord.detail(id, in: db)?.conflicts.first else { throw VerificationFailure(description: "Hidden conflict") }
            try check(conflict.mine == "Latest local title", "conflict shows value keep mine will submit")
        }
    }

    static func defaultPaginationScenario() async throws {
        struct Events: Decodable {
            struct Event: Decodable {
                struct Detail: Decodable { let limit: Int?; let ids: [String]?; let hasMore: Bool? }
                let device: String?
                let kind: String
                let detail: Detail
            }

            let events: [Event]
        }
        let baseURL = URL(string: ProcessInfo.processInfo.environment["POCKET_VERIFY_URL"] ?? "http://127.0.0.1:18787")!
        let database = try PocketDB.open(nil)
        let device = try await database.reader.read { try SyncStateRecord.load(in: $0).deviceID }
        let client = RestClient(.init(baseURL: baseURL, adapters: [StaticHeaders(["X-Device-Id": device])]))
        let supervisor = Supervisor(database: database, client: client)
        await supervisor.start()
        await supervisor.sync(.userRefresh)
        try await check(database.reader.read { try RecordingRecord.fetchCount($0) == 30 }, "first sync stores only the first 30 recordings")
        let newest = try await database.reader.read { try rows($0).first?.id.rawValue }
        try check(newest == "rec_0100", "first page holds the newest recordings")
        var counts: [Int] = []
        for _ in 0 ..< 4 {
            await supervisor.loadNextPage()
            try await counts.append(database.reader.read { try RecordingRecord.fetchCount($0) })
        }
        try check(counts == [60, 90, 100, 100], "each scroll page adds 30 recordings and stops at the end of the list")
        try await check(database.reader.read { try SyncStateRecord.load(in: $0).browseComplete }, "last page marks the list complete")
        let (data, response) = try await URLSession.shared.data(from: baseURL.appending(path: "logs/events"))
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw VerificationFailure(description: "Could not read pagination events")
        }
        let events = try JSONDecoder().decode(Events.self, from: data).events.filter { $0.device == device }
        let pages = events.filter { $0.kind == "browse" }
        try check(pages.map(\.detail.limit) == [30, 30, 30, 30], "browse requests 30 recordings per page")
        try check(pages.map { $0.detail.ids?.count } == [30, 30, 30, 10], "browse pages arrive as 30, 30, 30 and 10")
        try check(!events.contains { $0.kind == "list" && ($0.detail.ids?.count ?? 0) > 0 }, "the change feed downloads nothing when nothing changed")
        await supervisor.stop()
    }

    static func backendScenarios() async throws {
        let baseURL = URL(string: ProcessInfo.processInfo.environment["POCKET_VERIFY_URL"] ?? "http://127.0.0.1:18787")!
        let path = URL.temporaryDirectory.appending(path: "pocket-integration-\(UUID().uuidString).sqlite")
        defer { removeDatabase(path) }
        let fixture = try SyncFixture(path: path, serverURL: baseURL)
        let database = fixture.database
        let supervisor = fixture.supervisor
        await supervisor.start()
        await supervisor.sync(.userRefresh)
        let fetched = try await database.reader.read(rows)
        try check(fetched.count == 17, "Supervisor stores one browse page on first sync")
        guard let row = fetched.first else { throw VerificationFailure(description: "No server recordings") }
        let unbrowsedID = "rec_0001"
        let remoteSetup = RestClient(.init(baseURL: baseURL, adapters: [StaticHeaders(["X-Device-Id": "verification-other-device"])]))
        let unbrowsed = try await remoteSetup.send(VerifyGet(path: "/recordings/\(unbrowsedID)"))
        _ = try await remoteSetup.send(VerifyPatch(path: "/recordings/\(unbrowsedID)", body: .init(baseVersion: unbrowsed.version, title: "Edited before browsing")))
        await supervisor.sync(.userRefresh)
        try await check(database.reader.read { try RecordingRecord.fetchOne($0, key: unbrowsedID) == nil && RecordingRecord.fetchCount($0) == 17 },
                        "change feed skips an edit to a recording the list has not reached")
        await supervisor.setAirplaneMode(true)
        try await fixture.edit(row.id, set: [.title: "First queued integration title"])
        try await fixture.edit(row.id, set: [.title: "Offline integration title"])
        try await check(database.reader.read { try RecordingRecord.detail(row.id, in: $0)?.title == "Offline integration title" }, "offline edit changes observed recording")
        await supervisor.setAirplaneMode(false)
        await supervisor.sync(.userRefresh)
        let device = try await database.reader.read { try SyncStateRecord.load(in: $0).deviceID }
        let remote = RestClient(.init(baseURL: baseURL, adapters: [StaticHeaders(["X-Device-Id": "verification-other-device"])]))
        let detail = try await remote.send(VerifyGet(path: "/recordings/\(row.id)"))
        try check(detail.title == "Offline integration title", "reconnect sends queued title to backend")
        try await check(database.reader.read { try MutationRecord.next(in: $0) == nil }, "acknowledged mutation is removed")
        await supervisor.setAirplaneMode(true)
        try await fixture.edit(row.id, set: [.title: "Mine after offline"])
        _ = try await remote.send(VerifyPatch(path: "/recordings/\(row.id)", body: .init(baseVersion: detail.version, title: "Their concurrent title")))
        await supervisor.setAirplaneMode(false)
        await supervisor.sync(.userRefresh)
        let conflicted = try await database.reader.read { try RecordingRecord.detail(row.id, in: $0) }
        guard case let .field(field) = conflicted?.conflicts.first else { throw VerificationFailure(description: "Expected 409 conflict") }
        try check(field.mine == "Mine after offline" && field.theirs == "Their concurrent title", "409 exposes both conflict values")
        try await fixture.repository.resolve(field, .keepMine)
        await supervisor.sync(.userRefresh)
        let afterResolution = try await remote.send(VerifyGet(path: "/recordings/\(row.id)"))
        try check(afterResolution.title == "Mine after offline", "conflict resolution sends chosen value")
        var fault = URLRequest(url: baseURL.appending(path: "_sim/devices/\(device)"))
        fault.httpMethod = "PUT"
        fault.setValue("application/json", forHTTPHeaderField: "Content-Type")
        fault.httpBody = Data("{\"dropResponses\":1}".utf8)
        _ = try await URLSession.shared.data(for: fault)
        try await fixture.edit(row.id, set: [.summary: "Lost acknowledgment integration"])
        await supervisor.sync(.userRefresh)
        await supervisor.sync(.userRefresh)
        let afterReplay = try await remote.send(VerifyGet(path: "/recordings/\(row.id)"))
        try check(afterReplay.summary == "Lost acknowledgment integration", "lost acknowledgment retries safely")
        try await check(database.reader.read { try MutationRecord.next(in: $0) == nil }, "replayed acknowledgment removes mutation")
        try await fixture.repository.requestTranscript(row.id)
        await supervisor.sync(.userRefresh)
        let withTranscript = try await database.reader.read { try RecordingRecord.detail(row.id, in: $0) }
        guard case let .loaded(transcript) = withTranscript?.transcript else { throw VerificationFailure(description: "Transcript not cached") }
        try check(!transcript.segments.isEmpty, "transcript fetch is cached")
        await supervisor.setAirplaneMode(true)
        try await fixture.edit(row.id, set: [.summary: "Edit after remote delete"])
        _ = try await remote.send(VerifyDelete(path: "/recordings/\(row.id)", queryItems: [URLQueryItem(name: "baseVersion", value: String(afterReplay.version))]))
        await supervisor.setAirplaneMode(false)
        await supervisor.sync(.userRefresh)
        try await check(database.reader.read { try RecordingRecord.detail(row.id, in: $0) == nil }, "410 removes recording and queued edits")
        await supervisor.stop()
    }

    static func removeDatabase(_ path: URL) {
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path.path + suffix) }
    }
}

struct VerifyRecording: Decodable, Sendable { let title: String; let summary: String; let version: Int64 }
struct VerifyWrite: Decodable, Sendable { let recording: VerifyRecording }
struct VerifyGet: RestEndpoint {
    typealias Response = VerifyRecording
    let path: String
    var method: RestMethod { .get }
}

struct VerifyPatch: RestEndpoint {
    typealias Response = VerifyWrite
    struct Body: Encodable, Sendable { let baseVersion: Int64; let title: String }
    let path: String
    let body: Body?
    var method: RestMethod { .patch }
    var headers: [String: String] { ["Idempotency-Key": UUID().uuidString] }
}

struct VerifyDelete: RestEndpoint {
    typealias Response = EmptyResponse
    let path: String
    let queryItems: [URLQueryItem]
    var method: RestMethod { .delete }
    var headers: [String: String] { ["Idempotency-Key": UUID().uuidString] }
}
