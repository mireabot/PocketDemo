import Domain
import Foundation
import GRDB

public extension RecordingRecord {
    static func reconcile(_ id: RecordingID, in db: Database) throws {
        guard var record = try fetchOne(db, key: id.rawValue) else { return }
        let mutations = try MutationRecord.live(id, in: db)
        let hasConflict = mutations.contains { $0.status == .conflicted }
        let hasPending = mutations.contains { $0.status == .pending || $0.status == .inflight }
        let hasFailed = try MutationRecord.filter(MutationRecord.Columns.recordID == id.rawValue)
            .filter(MutationRecord.Columns.status == MutationStatus.failed.rawValue).fetchCount(db) > 0
        record.locallyDeleted = !hasConflict && mutations.contains { $0.action == .delete }
        record.sync = hasConflict ? .needsResolution : hasPending ? .pending : hasFailed ? .failed : .synced
        try record.update(db)
    }

    static func accept(_ server: Recording, generation: Int64? = nil, reset: Bool = false, in db: Database) throws {
        let stored = try fetchOne(db, key: server.id.rawValue)
        let seen = generation ?? stored?.seenGeneration ?? 0
        let replacesEpoch = reset && stored?.seenGeneration != seen
        if var stored, stored.version >= server.version, !replacesEpoch {
            if generation != nil {
                stored.seenGeneration = seen
                try stored.update(db)
            }
        } else {
            try RecordingRecord(server, generation: seen).save(db)
        }
        try reconcile(server.id, in: db)
    }

    static func remove(_ id: RecordingID, local: Bool = false, in db: Database) throws {
        guard let stored = try fetchOne(db, key: id.rawValue) else { return }
        if !local {
            let hasEdits = try MutationRecord.filter(MutationRecord.Columns.recordID == id.rawValue)
                .filter(MutationRecord.Columns.action == MutationAction.edit.rawValue).fetchCount(db) > 0
            if hasEdits {
                try NoticeRecord(recordingID: id.rawValue, title: stored.row(in: db).title).insert(db)
            }
        }
        _ = try deleteOne(db, key: id.rawValue)
    }
}
