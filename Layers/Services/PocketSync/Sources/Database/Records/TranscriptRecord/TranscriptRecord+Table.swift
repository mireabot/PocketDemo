import Domain
import Foundation
import GRDB

extension TranscriptRecord: MigratableTable {
    public static func createTable(table: TableDefinition) {
        table.column(Columns.recordingID.name, .text).primaryKey().references(RecordingRecord.databaseTableName, onDelete: .cascade)
        table.column(Columns.state.name, .text).notNull().check { ["wanted", "cached", "failed"].contains($0) }
        table.column(Columns.segments.name, .text)
        table.column(Columns.fetchedAt.name, .datetime)
        table.column(Columns.byteCount.name, .integer).notNull().defaults(to: 0)
        table.column(Columns.openedAt.name, .datetime).notNull().indexed()
        table.check((Columns.state == "cached" && Columns.segments != nil) || (Columns.state != "cached" && Columns.segments == nil))
    }
}
