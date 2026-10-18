import Domain
import Foundation
import GRDB

public extension MutationRecord {
    mutating func didInsert(_ inserted: InsertionSuccess) { sequence = inserted.rowID }

    private static var active: QueryInterfaceRequest<Self> {
        filter([MutationStatus.pending.rawValue, MutationStatus.inflight.rawValue, MutationStatus.conflicted.rawValue].contains(Columns.status))
    }

    static func live(_ id: RecordingID, in db: Database) throws -> [Self] {
        try active.filter(Columns.recordID == id.rawValue).order(Columns.sequence).fetchAll(db)
    }

    static func next(in db: Database) throws -> Self? {
        let rows = try active.order(Columns.sequence).fetchAll(db)
        let conflicts = rows.filter { $0.status == .conflicted }
        for row in rows where row.status == .pending || row.status == .inflight {
            let blocking = conflicts.filter { $0.recordID == row.recordID }
            if blocking.contains(where: { $0.action == .delete }) { continue }
            if row.action == .delete, !blocking.isEmpty { continue }
            if let field = row.field, blocking.contains(where: { $0.field == field }) { continue }
            return row
        }
        return nil
    }

    static func claim(in db: Database) throws -> Self? {
        guard var mutation = try next(in: db) else { return nil }
        mutation.status = .inflight
        try mutation.update(db)
        try RecordingRecord.reconcile(RecordingID(mutation.recordID), in: db)
        return mutation
    }
}
