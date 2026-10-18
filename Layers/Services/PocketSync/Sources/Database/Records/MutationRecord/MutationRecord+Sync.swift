import Domain
import Foundation
import GRDB

public extension MutationRecord {
    static func acknowledge(_ mutation: Self, server: Recording?, in db: Database) throws {
        let id = RecordingID(mutation.recordID)
        guard let server else {
            try RecordingRecord.remove(id, local: true, in: db)
            return
        }
        try remove(mutation, in: db)
        try RecordingRecord.accept(server, in: db)
        try RecordingRecord.reconcile(id, in: db)
    }

    static func recordConflict(_ mutation: Self, current: Recording, fields: Set<EditableField>,
                               changedBy: String?, changedAt: Date, mayRebase: Bool, in db: Database) throws -> ConflictDecision
    {
        try RecordingRecord.accept(current, in: db)
        guard let stored = try RecordingRecord.fetchOne(db, key: mutation.recordID) else { return .drop }
        let decision = decide(mutation, server: stored.recording, mayRebase: mayRebase)
        switch decision {
        case .drop: try remove(mutation, in: db)
        case .rebase: try replaceAfterRejection(mutation, server: stored.recording, in: db)
        case .askUser:
            var rejected = mutation
            rejected.status = .conflicted
            try rejected.update(db)
            try ConflictRecord(mutationID: mutation.id, changedFields: fields,
                               changedBy: changedBy, changedAt: changedAt).save(db)
        }
        try RecordingRecord.reconcile(current.id, in: db)
        return decision
    }

    static func reconcileConflicts(_ ids: [RecordingID], in db: Database) throws {
        for id in ids {
            guard let record = try RecordingRecord.fetchOne(db, key: id.rawValue) else { continue }
            for mutation in try live(id, in: db) where mutation.status == .conflicted {
                switch decide(mutation, server: record.recording, mayRebase: true) {
                case .drop: try remove(mutation, in: db)
                case .rebase: try replaceAfterRejection(mutation, server: record.recording, in: db)
                case .askUser: break
                }
            }
            try RecordingRecord.reconcile(id, in: db)
        }
    }

    func fail(_ reason: String, in db: Database) throws {
        _ = try ConflictRecord.deleteOne(db, key: id)
        var failed = self
        failed.status = .failed
        failed.failureReason = reason
        try failed.update(db)
        try RecordingRecord.reconcile(RecordingID(recordID), in: db)
    }

    static func discardFailed(_ id: RecordingID, in db: Database) throws {
        _ = try filter(Columns.recordID == id.rawValue)
            .filter(Columns.status == MutationStatus.failed.rawValue).deleteAll(db)
        try RecordingRecord.reconcile(id, in: db)
    }

    internal static func replaceAfterRejection(_ mutation: Self, server: Recording, in db: Database) throws {
        _ = try ConflictRecord.deleteOne(db, key: mutation.id)
        var replacement = mutation
        replacement.id = UUID().uuidString
        replacement.status = .pending
        replacement.failureReason = nil
        replacement.baseVersion = server.version
        replacement.oldValue = mutation.field.map { $0 == .title ? server.title : server.summary }
        try replacement.update(db)
    }

    private static func decide(_ mutation: Self, server: Recording, mayRebase: Bool) -> ConflictDecision {
        guard mutation.action == .edit, let field = mutation.field else { return .askUser }
        let theirs = field == .title ? server.title : server.summary
        if theirs == mutation.newValue { return .drop }
        if theirs == mutation.oldValue, mayRebase { return .rebase }
        return .askUser
    }

    internal static func remove(_ mutation: Self, in db: Database) throws {
        _ = try filter(Columns.id == mutation.id).deleteAll(db)
    }
}
