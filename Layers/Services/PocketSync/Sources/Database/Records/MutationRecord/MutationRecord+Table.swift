import Domain
import Foundation
import GRDB

extension MutationRecord: MigratableTable {
    public static func createTable(table: TableDefinition) {
        table.autoIncrementedPrimaryKey(Columns.sequence.name)
        table.column(Columns.id.name, .text).notNull().unique()
        table.column(Columns.recordID.name, .text).notNull().indexed().references(RecordingRecord.databaseTableName, onDelete: .cascade)
        table.column(Columns.action.name, .text).notNull().check { ["edit", "delete"].contains($0) }
        table.column(Columns.field.name, .text).check { $0 == nil || ["title", "summary"].contains($0) }
        table.column(Columns.oldValue.name, .text)
        table.column(Columns.newValue.name, .text)
        table.column(Columns.baseVersion.name, .integer).notNull()
        table.column(Columns.status.name, .text).notNull().indexed().check { ["pending", "inflight", "conflicted", "failed"].contains($0) }
        table.column(Columns.createdAt.name, .datetime).notNull()
        table.column(Columns.failureReason.name, .text)
        let deleteFields: SQLExpression = (Columns.field == nil && Columns.oldValue == nil && Columns.newValue == nil)
        let editFields: SQLExpression = (Columns.field != nil && Columns.oldValue != nil && Columns.newValue != nil)
        let deleteShape: SQLExpression = (Columns.action == "delete" && deleteFields)
        let editShape: SQLExpression = (Columns.action == "edit" && editFields)
        table.check(deleteShape || editShape)
    }
}
