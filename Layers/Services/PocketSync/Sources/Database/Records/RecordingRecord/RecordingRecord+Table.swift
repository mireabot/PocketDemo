import Domain
import Foundation
import GRDB

extension RecordingRecord: MigratableTable {
    public static func createTable(table: TableDefinition) {
        table.column(Columns.id.name, .text).primaryKey()
        table.column(Columns.title.name, .text).notNull()
        table.column(Columns.summary.name, .text).notNull()
        table.column(Columns.version.name, .integer).notNull()
        table.column(Columns.createdAt.name, .datetime).notNull().indexed()
        table.column(Columns.updatedAt.name, .datetime).notNull()
        table.column(Columns.updatedBy.name, .text)
        table.column(Columns.segmentCount.name, .integer).notNull()
        table.column(Columns.seenGeneration.name, .integer).notNull()
        table.column(Columns.locallyDeleted.name, .boolean).notNull()
        table.column(Columns.sync.name, .text).notNull()
    }
}
