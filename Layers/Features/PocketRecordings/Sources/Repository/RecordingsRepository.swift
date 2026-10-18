import Dependencies
import Domain
import Foundation
import PocketSync

struct RecordingsRepository: Sendable {
    @Dependency(\.pocketDB) private var database
    @Dependency(\.supervisor) private var supervisor

    func sections() -> AsyncValueObservation<RecordingSections> {
        ValueObservation.tracking { db in
            let rows = try RecordingRecord.visible.order(RecordingRecord.Columns.createdAt.desc, RecordingRecord.Columns.id.desc).fetchAll(db).map { try $0.row(in: db) }
            return try RecordingSections(needsAttention: rows.filter { $0.sync == .needsResolution || $0.sync == .failed },
                                         all: rows.filter { $0.sync != .needsResolution && $0.sync != .failed },
                                         hasMore: !SyncStateRecord.load(in: db).browseComplete)
        }.removeDuplicates().values(in: database.reader)
    }

    func recording(_ id: RecordingID) -> AsyncValueObservation<RecordingDetail?> {
        ValueObservation.tracking { try RecordingRecord.detail(id, in: $0) }.removeDuplicates().values(in: database.reader)
    }

    func status() -> AsyncValueObservation<SyncStatus> {
        ValueObservation.tracking { try SyncStateRecord.status(in: $0) }.removeDuplicates().values(in: database.reader)
    }

    func notices() -> AsyncValueObservation<[Notice]> {
        ValueObservation.tracking { try NoticeRecord.order(NoticeRecord.Columns.createdAt, NoticeRecord.Columns.id).fetchAll($0).map(\.notice) }.removeDuplicates().values(in: database.reader)
    }

    func refresh() async { await supervisor.sync(.userRefresh) }
    func loadNextPage() async { await supervisor.loadNextPage() }
    func setAirplaneMode(_ on: Bool) async { await supervisor.setAirplaneMode(on) }

    func save(_ draft: RecordingDraft, simulating simulation: NetworkSimulation? = nil) async throws {
        let changes = draft.changes
        if let simulation { await supervisor.simulate(simulation, onNextWriteTo: draft.id) }
        try await database.writer.write { db in
            for field in EditableField.allCases {
                if let value = changes[field] {
                    try MutationRecord.edit(draft.id, field: field, value: value, basedOn: draft.original.base, in: db)
                }
            }
        }
        await supervisor.wake(.drain)
    }

    func delete(_ id: RecordingID) async throws {
        try await database.writer.write { try MutationRecord.delete(id, in: $0) }
        await supervisor.wake(.drain)
    }

    func resolve(_ conflict: FieldConflict, _ resolution: FieldResolution) async throws {
        try await database.writer.write { try MutationRecord.resolve(conflict, with: resolution, in: $0) }
        await supervisor.wake(.drain)
    }

    func resolve(_ conflict: DeleteConflict, _ resolution: DeleteResolution) async throws {
        try await database.writer.write { try MutationRecord.resolve(conflict, with: resolution, in: $0) }
        await supervisor.wake(.drain)
    }

    func dismiss(_ notice: Notice) async throws {
        _ = try await database.writer.write { try NoticeRecord.deleteOne($0, key: notice.id) }
    }

    func requestTranscript(_ id: RecordingID) async throws {
        try await database.writer.write { try TranscriptRecord.request(id, in: $0) }
        await supervisor.wake(.transcripts)
    }

    func discardFailedChanges(_ id: RecordingID) async throws {
        try await database.writer.write { try MutationRecord.discardFailed(id, in: $0) }
    }

    static func message(_ error: any Error) -> String {
        guard let error = error as? IntentError else { return "Couldn't save on this device." }
        switch error {
        case .recordingNotFound, .recordingDeleted: return "This recording no longer exists."
        case .blankTitle: return "Enter a title."
        case let .tooLong(field, max): return "The \(field.rawValue) must be at most \(max) characters."
        case .unresolvedConflict, .conflictNeedsResolution: return "Resolve the recording's conflict first."
        case .storageFailed: return "Couldn't save on this device. Your change was not saved."
        }
    }
}
