import Domain
import Foundation
import GRDB
import OSLog
import PocketNetworking

public actor Supervisor {
    public struct Scope: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let drain = Self(rawValue: 1)
        public static let pull = Self(rawValue: 2)
        public static let transcripts = Self(rawValue: 4)
        public static let retryTranscripts = Self(rawValue: 8)
        public static let nextPage = Self(rawValue: 16)
        public static let full: Self = [.drain, .pull, .transcripts]
    }

    private enum Lifecycle { case cold, booting, ready, stopped }
    private enum Halt: Error { case offline, retry(String), cancelled }
    private struct Waiter {
        let afterPass: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    let database: PocketDB
    let client: RestClient
    private let api: PocketAPI
    private let pageSize: Int
    private var lifecycle = Lifecycle.cold
    private var requested: Scope = []
    private var loop: Task<Void, Never>?
    private var connectivityWatch: Task<Void, Never>?
    private var retry: Task<Void, Never>?
    private var attempt = 0
    private var passesStarted = 0
    private var waiters: [UUID: Waiter] = [:]
    private var airplaneRevision = 0
    private var resetsInPass = 0
    private var simulations: [String: NetworkSimulation] = [:]

    public init(database: PocketDB, client: RestClient, pageSize: Int = 30) {
        self.database = database
        self.client = client
        api = PocketAPI(client: client)
        self.pageSize = pageSize
    }

    deinit {
        loop?.cancel()
        connectivityWatch?.cancel()
        retry?.cancel()
        for waiter in waiters.values {
            waiter.continuation.resume()
        }
    }

    public func start() async { await boot() }

    private func boot() async {
        guard lifecycle == .cold else { return }
        lifecycle = .booting
        let revision = airplaneRevision
        do {
            let state = try await database.reader.read { try SyncStateRecord.load(in: $0) }
            if revision == airplaneRevision { await client.setOffline(state.airplaneMode) }
            guard lifecycle != .stopped else { return }
            lifecycle = .ready
            connectivityWatch = Task { [weak self, client] in
                var last: Connectivity?
                for await value in await client.connectivityUpdates() {
                    guard !Task.isCancelled else { return }
                    if value == .online, let last, last != .online { await self?.wake(.full) }
                    last = value
                }
            }
            wake(.full)
        } catch {
            lifecycle = .cold
            await recordError(error)
            finishAllWaiters()
        }
    }

    public func wake(_ scope: Scope) {
        guard lifecycle != .stopped else { return }
        requested.formUnion(scope)
        guard lifecycle == .ready, loop == nil else { return }
        loop = Task { [weak self] in await self?.runLoop() }
    }

    public func sync(_ trigger: SyncTrigger) async {
        await run(trigger == .userRefresh ? [.full, .retryTranscripts] : .full)
    }

    /// Fetches the next browse page of the list and returns after the pass that handled it.
    public func loadNextPage() async { await run(.nextPage) }

    private func run(_ scope: Scope) async {
        if lifecycle == .cold { await boot() }
        guard lifecycle == .ready || lifecycle == .booting else { return }
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(); return }
                waiters[id] = Waiter(afterPass: passesStarted, continuation: continuation)
                wake(scope)
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    /// Applies `simulation` to the next write sent for `id`. A retry of that write goes out normally.
    public func simulate(_ simulation: NetworkSimulation, onNextWriteTo id: RecordingID) {
        simulations[id.rawValue] = simulation
    }

    public func setAirplaneMode(_ on: Bool) async {
        airplaneRevision += 1
        let revision = airplaneRevision
        await client.setOffline(on)
        guard revision == airplaneRevision else { return }
        if on { retry?.cancel(); retry = nil }
        do {
            try await database.writer.write { db in
                var state = try SyncStateRecord.load(in: db)
                state.airplaneMode = on
                if on { state.phase = .waitingForNetwork }
                try state.update(db)
            }
            if revision == airplaneRevision, !on { wake(.full) }
        } catch { await recordError(error) }
    }

    func stop() {
        lifecycle = .stopped
        requested = []
        loop?.cancel()
        connectivityWatch?.cancel()
        retry?.cancel()
        finishAllWaiters()
    }

    private func runLoop() async {
        while !requested.isEmpty, !Task.isCancelled, lifecycle == .ready {
            let scope = requested
            requested = []
            passesStarted += 1
            let number = passesStarted
            await pass(scope)
            for (id, waiter) in waiters where waiter.afterPass < number {
                waiters.removeValue(forKey: id)?.continuation.resume()
            }
        }
        loop = nil
    }

    private func pass(_ scope: Scope) async {
        do {
            guard await client.currentConnectivity == .online else { throw Halt.offline }
            try await database.writer.write { db in
                var state = try SyncStateRecord.load(in: db)
                state.phase = .syncing
                state.lastError = nil
                try state.update(db)
                if scope.contains(.retryTranscripts) { try TranscriptRecord.filter(TranscriptRecord.Columns.state == TranscriptRecord.State.failed.rawValue).updateAll(db, TranscriptRecord.Columns.state.set(to: TranscriptRecord.State.wanted.rawValue)) }
            }
            resetsInPass = 0
            if try await currentState().resetting { try await finishReset() }
            if try await currentState().needsFirstPage { try await browse() }
            if scope.contains(.drain) { try await drain() }
            if scope.contains(.pull) { try await pull() }
            if scope.contains(.transcripts) { try await fetchTranscripts() }
            if scope.contains(.nextPage) { try await browse() }
            if try await database.reader.read({ try MutationRecord.next(in: $0) != nil }) { requested.insert(.drain) }
            try Task.checkCancellation()
            try await database.writer.write { db in
                var state = try SyncStateRecord.load(in: db)
                state.phase = .idle
                state.lastError = nil
                if scope.contains(.pull) {
                    state.lastSyncedAt = Date()
                }
                try state.update(db)
            }
            attempt = 0
            retry?.cancel()
            retry = nil
        } catch Halt.offline {
            do {
                try await database.writer.write { db in
                    var state = try SyncStateRecord.load(in: db)
                    state.phase = .waitingForNetwork
                    try state.update(db)
                }
            } catch {
                await recordError(error)
            }
        } catch Halt.cancelled {
            return
        } catch is CancellationError {
            return
        } catch {
            await recordError(error)
            scheduleRetry()
        }
    }

    private func drain() async throws {
        var rebased: Set<Int64?> = []
        while !Task.isCancelled {
            if try await currentState().resetting { try await finishReset() }
            guard let mutation = try await database.writer.write({ try MutationRecord.claim(in: $0) }) else { return }
            let simulation = simulations.removeValue(forKey: mutation.recordID)
            // A simulated cut acts like losing the network: the write waits in the local database,
            // with no automatic retry, until a refresh, the airplane switch or the next foreground.
            if simulation == .neverSent { throw Halt.offline }
            let outcome = await api.send(mutation, simulating: simulation)
            if simulation == .lostReply, case .retryLater = outcome { throw Halt.offline }
            switch outcome {
            case let .applied(server):
                try await database.writer.write { try MutationRecord.acknowledge(mutation, server: server, in: $0) }
            case let .conflict(conflict):
                let mayRebase = !rebased.contains(mutation.sequence)
                let result = try await database.writer.write { try MutationRecord.recordConflict(mutation, current: conflict.current, fields: conflict.fields, changedBy: conflict.changedBy, changedAt: conflict.changedAt, mayRebase: mayRebase, in: $0) }
                if result == .rebase { rebased.insert(mutation.sequence) }
            case .gone:
                try await database.writer.write { try RecordingRecord.remove(RecordingID(mutation.recordID), in: $0) }
            case .serverReset:
                try await reset()
            case let .rejected(reason):
                try await database.writer.write { try mutation.fail(reason, in: $0) }
            case .offline: throw Halt.offline
            case let .retryLater(reason): throw Halt.retry(reason)
            case .cancelled: throw Halt.cancelled
            }
        }
        throw CancellationError()
    }

    private func currentState() async throws -> SyncStateRecord {
        try await database.reader.read { try SyncStateRecord.load(in: $0) }
    }

    /// Follows the change feed from the saved sync cursor. Edits to recordings the user has not
    /// browsed to yet are skipped: browsing reaches them later with their current values.
    private func pull() async throws {
        var seenCursors: Set<String> = []
        while !Task.isCancelled {
            guard let cursor = try await currentState().cursor else { return }
            switch await api.feed(cursor: cursor, limit: pageSize) {
            case let .page(page):
                if page.hasMore, page.nextCursor == cursor || !seenCursors.insert(page.nextCursor).inserted { throw Halt.retry("Feed cursor did not advance") }
                try await database.writer.write { db in
                    var sync = try SyncStateRecord.load(in: db)
                    var ids: [RecordingID] = []
                    for item in page.items {
                        switch item {
                        case let .live(server):
                            guard try RecordingRecord.exists(db, key: server.id.rawValue) || sync.hasBrowsed(server) else { continue }
                            try RecordingRecord.accept(server, in: db)
                            ids.append(server.id)
                        case let .deleted(id): try RecordingRecord.remove(id, in: db)
                        }
                    }
                    try MutationRecord.reconcileConflicts(ids, in: db)
                    sync.cursor = page.nextCursor
                    try sync.update(db)
                }
                if !page.hasMore { return }
            case .cursorReset:
                try await reset()
                seenCursors = []
            case .offline: throw Halt.offline
            case let .retryLater(reason): throw Halt.retry(reason)
            case .cancelled: throw Halt.cancelled
            }
        }
        throw CancellationError()
    }

    /// Fetches the next page of the list, newest first. Without a sync cursor the first page also sets it,
    /// so later edits and deletes arrive through `pull` instead of a download of every recording.
    private func browse() async throws {
        let state = try await currentState()
        guard !state.browseComplete else { return }
        switch await api.browse(after: state.browseCursor, limit: pageSize) {
        case let .page(page):
            try await database.writer.write { db in
                var sync = try SyncStateRecord.load(in: db)
                for server in page.items {
                    try RecordingRecord.accept(server, generation: sync.generation, reset: sync.resetting, in: db)
                }
                if !sync.resetting { try MutationRecord.reconcileConflicts(page.items.map(\.id), in: db) }
                if sync.cursor == nil { sync.cursor = page.syncCursor }
                sync.browseCursor = page.nextCursor
                sync.browseComplete = !page.hasMore
                if let last = page.items.last {
                    sync.browseEdge = last.createdAt
                    sync.browseEdgeID = last.id.rawValue
                }
                try sync.update(db)
            }
        case .cursorReset: try await reset()
        case .offline: throw Halt.offline
        case let .retryLater(reason): throw Halt.retry(reason)
        case .cancelled: throw Halt.cancelled
        }
    }

    /// The server database was replaced: drop the cache, browse again from the top and refresh
    /// recordings that still have local work before any of that work is sent.
    private func reset() async throws {
        guard resetsInPass == 0 else { throw Halt.retry("Server reset repeatedly") }
        resetsInPass += 1
        try await database.writer.write { try SyncStateRecord.beginReset(in: $0) }
        try await finishReset()
    }

    private func finishReset() async throws {
        if try await currentState().needsFirstPage { try await browse() }
        for id in try await database.reader.read({ try SyncStateRecord.unrefreshed(in: $0) }) {
            try Task.checkCancellation()
            switch await api.detail(id) {
            case let .found(server, _):
                try await database.writer.write { db in
                    let state = try SyncStateRecord.load(in: db)
                    try RecordingRecord.accept(server, generation: state.generation, reset: true, in: db)
                }
            case .gone: try await database.writer.write { try RecordingRecord.remove(id, in: $0) }
            case .offline: throw Halt.offline
            case let .retryLater(reason): throw Halt.retry(reason)
            case .cancelled: throw Halt.cancelled
            }
        }
        try await database.writer.write { try SyncStateRecord.endReset(in: $0) }
    }

    private func fetchTranscripts() async throws {
        let ids = try await database.reader.read { try TranscriptRecord.wanted.fetchAll($0).map(\.recordingID) }
        for raw in ids {
            try Task.checkCancellation()
            let id = RecordingID(raw)
            switch await api.detail(id) {
            case let .found(server, segments):
                try await database.writer.write { db in
                    guard try RecordingRecord.fetchOne(db, key: id.rawValue) != nil else { return }
                    try RecordingRecord.accept(server, in: db)
                    try TranscriptRecord.store(id, segments: segments, in: db)
                }
            case .gone: try await database.writer.write { try RecordingRecord.remove(id, in: $0) }
            case .offline: throw Halt.offline
            case .retryLater:
                _ = try await database.writer.write { try TranscriptRecord.filter(TranscriptRecord.Columns.recordingID == raw).updateAll($0, TranscriptRecord.Columns.state.set(to: TranscriptRecord.State.failed.rawValue)) }
            case .cancelled: throw Halt.cancelled
            }
        }
    }

    private func recordError(_ error: any Error) async {
        let message = String(describing: error)
        Logger(subsystem: "PocketDemo", category: "Sync").error("Sync stopped: \(message, privacy: .public)")
        do {
            try await database.writer.write { db in
                var state = try SyncStateRecord.load(in: db)
                state.phase = .retrying
                state.lastError = message
                try state.update(db)
            }
        } catch {
            Logger(subsystem: "PocketDemo", category: "Sync").error("Could not save sync status: \(String(describing: error), privacy: .public)")
        }
    }

    private func scheduleRetry() {
        guard lifecycle == .ready else { return }
        retry?.cancel()
        let seconds = min(30, 1 << min(attempt, 5))
        attempt += 1
        retry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            await self?.wake(.full)
        }
    }

    private func cancelWaiter(_ id: UUID) { waiters.removeValue(forKey: id)?.continuation.resume() }
    private func finishAllWaiters() {
        let pending = waiters.values
        waiters = [:]
        for waiter in pending {
            waiter.continuation.resume()
        }
    }
}
