import Domain
import Foundation
import GRDB

public extension SyncStateRecord {
    static func load(in db: Database) throws -> Self {
        guard let state = try fetchOne(db, key: 1) else { throw DatabaseError(message: "Missing sync state") }
        return state
    }

    /// The list has not loaded its first page yet: a first launch or a finished server reset.
    var needsFirstPage: Bool { browseCursor == nil && !browseComplete }

    /// True when a recording at this position belongs to the part of the list already browsed.
    func hasBrowsed(_ recording: Recording) -> Bool {
        if browseComplete { return true }
        guard let browseEdge, let browseEdgeID else { return false }
        return recording.createdAt > browseEdge || (recording.createdAt == browseEdge && recording.id.rawValue >= browseEdgeID)
    }

    /// The server database was replaced. Rows without local work are only a cache, so they go;
    /// rows with mutations stay until `endReset` refreshes or removes them.
    static func beginReset(in db: Database) throws {
        var state = try load(in: db)
        state.cursor = nil
        state.browseCursor = nil
        state.browseComplete = false
        state.browseEdge = nil
        state.browseEdgeID = nil
        state.generation += 1
        state.resetting = true
        try state.update(db)
        try TranscriptRecord.invalidate(in: db)
        let kept = try MutationRecord.select(MutationRecord.Columns.recordID, as: String.self).distinct().fetchAll(db)
        try RecordingRecord.filter(!kept.contains(RecordingRecord.Columns.id)).deleteAll(db)
    }

    /// Recordings with local work that the new server copy has not reached yet.
    static func unrefreshed(in db: Database) throws -> [RecordingID] {
        let state = try load(in: db)
        return try RecordingRecord.filter(RecordingRecord.Columns.seenGeneration < state.generation)
            .select(RecordingRecord.Columns.id, as: String.self).fetchAll(db).map(RecordingID.init)
    }

    static func endReset(in db: Database) throws {
        var state = try load(in: db)
        let pending = try MutationRecord.filter([MutationStatus.pending.rawValue, MutationStatus.inflight.rawValue].contains(MutationRecord.Columns.status))
            .order(MutationRecord.Columns.sequence).fetchAll(db)
        for mutation in pending {
            guard let record = try RecordingRecord.fetchOne(db, key: mutation.recordID) else { continue }
            try MutationRecord.replaceAfterRejection(mutation, server: record.recording, in: db)
        }
        let records = try RecordingRecord.fetchAll(db)
        try MutationRecord.reconcileConflicts(records.map { RecordingID($0.id) }, in: db)
        for record in records {
            try RecordingRecord.reconcile(RecordingID(record.id), in: db)
        }
        state.resetting = false
        try state.update(db)
    }

    static func status(in db: Database) throws -> SyncStatus {
        let state = try load(in: db)
        let phase: SyncStatus.Phase = switch state.phase {
        case .idle: .idle(lastSyncedAt: state.lastSyncedAt)
        case .syncing: .syncing
        case .waitingForNetwork: .waitingForNetwork
        case .retrying: .retrying(message: state.lastError ?? "Connection interrupted")
        }
        return try SyncStatus(phase: phase, isAirplaneModeOn: state.airplaneMode,
                              pendingCount: MutationRecord.filter([MutationStatus.pending.rawValue, MutationStatus.inflight.rawValue].contains(MutationRecord.Columns.status)).fetchCount(db),
                              conflictCount: MutationRecord.filter(MutationRecord.Columns.status == MutationStatus.conflicted.rawValue).fetchCount(db),
                              failedCount: MutationRecord.filter(MutationRecord.Columns.status == MutationStatus.failed.rawValue).fetchCount(db))
    }
}
