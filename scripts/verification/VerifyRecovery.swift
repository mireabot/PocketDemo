import Domain
import Foundation
import GRDB
import PocketNetworking
@testable import PocketSync

enum RecoveryChecks {
    static func run() async throws {
        let baseURL = URL(string: ProcessInfo.processInfo.environment["POCKET_VERIFY_URL"] ?? "http://127.0.0.1:18787")!
        var control = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        control.port = (control.port ?? 80) + 1
        let controlURL = control.url!
        let path = URL.temporaryDirectory.appending(path: "pocket-recovery-\(UUID().uuidString).sqlite")
        defer { VerifySync.removeDatabase(path) }
        let firstEpoch = try await reset(controlURL)
        let remote = RestClient(.init(baseURL: baseURL, adapters: [StaticHeaders(["X-Device-Id": "recovery-other-device"])]))
        // rec_0060 sits on the third page of 17, so after a reset the first page alone does not refresh it.
        let id = RecordingID("rec_0060")
        let original = try await remote.send(VerifyGet(path: "/recordings/\(id)"))
        let bumped = try await remote.send(VerifyPatch(path: "/recordings/\(id)", body: .init(baseVersion: original.version, title: "Title before reset")))
        let fixture = try SyncFixture(path: path, serverURL: baseURL)
        await fixture.supervisor.start()
        await fixture.supervisor.sync(.userRefresh)
        await fixture.supervisor.loadNextPage()
        await fixture.supervisor.loadNextPage()
        try await check(fixture.database.reader.read { try RecordingRecord.fetchCount($0) == 51 && RecordingRecord.fetchOne($0, key: id.rawValue) != nil },
                        "recovery starts with three browsed pages including the edited recording")
        try await fixture.repository.requestTranscript(id)
        await fixture.supervisor.sync(.userRefresh)
        let cached = try await fixture.database.reader.read { try TranscriptRecord.fetchOne($0, key: id.rawValue) }
        try check(cached?.state == .cached && cached?.segments?.isEmpty == false, "recovery starts with cached transcript")
        let device = try await fixture.database.reader.read { try SyncStateRecord.load(in: $0).deviceID }
        await fixture.supervisor.setAirplaneMode(true)
        let localSummary = "Edit saved before the server reset"
        try await fixture.edit(id, set: [.summary: localSummary])
        let before = try await fixture.database.reader.read { try SyncStateRecord.load(in: $0) }
        let lastEvent = try await events(baseURL).last?.id ?? 0
        try await latency(baseURL, device: device, milliseconds: 1000)
        let secondEpoch = try await reset(controlURL)
        try check(firstEpoch != secondEpoch, "isolated backend reset changes the actual server epoch")

        try await withDeadline {
            let observation = ValueObservation.tracking { db in
                let state = try SyncStateRecord.load(in: db)
                return RecoveryProgress(resetting: state.resetting, cursor: state.cursor, generation: state.generation)
            }.values(in: fixture.database.reader)
            var values = observation.makeAsyncIterator()
            _ = try await values.next()
            await fixture.supervisor.setAirplaneMode(false)
            while let progress = try await values.next() {
                if progress.resetting, progress.cursor != nil, progress.generation == before.generation + 1 {
                    await fixture.supervisor.setAirplaneMode(true)
                    return
                }
            }
            throw VerificationFailure(description: "Recovery observation ended before the first page committed")
        }
        await fixture.supervisor.sync(.userRefresh)
        let interrupted = try await fixture.database.reader.read { try SyncStateRecord.load(in: $0) }
        try check(interrupted.resetting && interrupted.cursor != nil && interrupted.cursor != before.cursor,
                  "first page after the reset and its sync cursor commit before the offline interruption")
        try check(interrupted.generation == before.generation + 1, "a real server reset begins one new generation")
        try await fixture.database.reader.read { db in
            try check(RecordingRecord.fetchCount(db) == 18, "reset replaces the cache with the first page and keeps the edited recording")
            try check(RecordingRecord.fetchOne(db, key: "rec_0100")?.title.hasPrefix("Epoch 2:") == true, "first page after the reset comes from the new server")
            let transcript = try TranscriptRecord.fetchOne(db, key: id.rawValue)
            try check(transcript?.state == .wanted && transcript?.segments == nil, "server reset clears the cached transcript and keeps its request")
            try check(RecordingRecord.fetchOne(db, key: id.rawValue)?.version == bumped.recording.version,
                      "the interrupted reset has not yet refreshed the edited recording")
            try check(RecordingRecord.detail(id, in: db)?.summary == localSummary, "edit stays visible during the interrupted reset")
        }
        await fixture.supervisor.stop()

        let resumed = try SyncFixture(path: path, serverURL: baseURL)
        try await resumed.database.reader.read { db in
            let state = try SyncStateRecord.load(in: db)
            try check(state.resetting && state.cursor == interrupted.cursor && state.generation == interrupted.generation,
                      "reopened database retains the unfinished reset")
            try check(RecordingRecord.detail(id, in: db)?.summary == localSummary && MutationRecord.live(id, in: db).count == 1,
                      "reopened database retains the displayed edit and its mutation row")
        }
        try await latency(baseURL, device: device, milliseconds: 0)
        await resumed.supervisor.start()
        await resumed.supervisor.setAirplaneMode(false)
        await resumed.supervisor.sync(.userRefresh)
        try await resumed.database.reader.read { db in
            let state = try SyncStateRecord.load(in: db)
            try check(!state.resetting && state.generation == interrupted.generation, "reopened Supervisor finishes the existing reset without starting another")
            try check(RecordingRecord.detail(id, in: db)?.summary == localSummary && MutationRecord.next(in: db) == nil,
                      "reset keeps the edit, rebases it and sends it")
            let transcript = try TranscriptRecord.fetchOne(db, key: id.rawValue)
            try check(transcript?.state == .cached && transcript?.segments?.first?.text.hasPrefix("Epoch 2:") == true,
                      "kept transcript request fetches the new server's transcript")
        }
        let recoveryEvents = try await events(baseURL).filter { $0.id > lastEvent && $0.device == device }
        let writes = recoveryEvents.filter { $0.method == "PATCH" }
        try check(writes.first?.status == 422 && writes.last?.kind == "edit.applied" && writes.count == 2,
                  "the stale edit is refused as base_version_ahead and the rebased edit applies once")
        try check(recoveryEvents.filter { $0.kind == "browse" && $0.detail.after == nil }.count == 1,
                  "the resumed reset does not browse the first page again")
        let recovered = try await remote.send(VerifyGet(path: "/recordings/\(id)"))
        try check(recovered.title.hasPrefix("Epoch 2:") && recovered.summary == localSummary,
                  "server keeps its reset title and receives the local summary")
        try await check(resumed.database.reader.read { try RecordingRecord.fetchOne($0, key: id.rawValue)?.version } == recovered.version,
                        "local copy matches the new server after the rebased write")
        await resumed.supervisor.stop()
    }

    private static func reset(_ controlURL: URL) async throws -> String {
        struct Result: Decodable { let epoch: String; let recordings: Int }
        var request = URLRequest(url: controlURL.appending(path: "reset"))
        request.httpMethod = "POST"
        let data = try await send(request)
        let result = try JSONDecoder().decode(Result.self, from: data)
        try check(result.recordings == 100, "verification backend reseeds 100 recordings in memory")
        return result.epoch
    }

    private static func latency(_ baseURL: URL, device: String, milliseconds: Int) async throws {
        var request = URLRequest(url: baseURL.appending(path: "_sim/devices/\(device)"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["latencyMs": milliseconds])
        _ = try await send(request)
    }

    private static func events(_ baseURL: URL) async throws -> [RecoveryEvent] {
        struct Result: Decodable { let events: [RecoveryEvent] }
        let data = try await send(URLRequest(url: baseURL.appending(path: "logs/events")))
        return try JSONDecoder().decode(Result.self, from: data).events
    }

    private static func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200 ..< 300).contains(response.statusCode) else {
            throw VerificationFailure(description: "Recovery control request failed for \(request.url?.path ?? "unknown")")
        }
        return data
    }

    private static func withDeadline(_ operation: @escaping @Sendable () async throws -> Void) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask(operation: operation)
            group.addTask {
                try await Task.sleep(for: .seconds(15))
                throw VerificationFailure(description: "Timed out waiting for recovery database observation")
            }
            defer { group.cancelAll() }
            _ = try await group.next()
        }
    }
}

private struct RecoveryProgress: Sendable {
    let resetting: Bool
    let cursor: String?
    let generation: Int64
}

private struct RecoveryEvent: Decodable {
    struct Detail: Decodable { let hasMore: Bool?; let after: String? }
    let id: Int
    let device: String?
    let method: String
    let status: Int
    let kind: String
    let detail: Detail
}
