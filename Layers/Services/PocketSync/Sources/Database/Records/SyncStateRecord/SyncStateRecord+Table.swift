import Domain
import Foundation
import GRDB

extension SyncStateRecord: MigratableTable {
    public static func createTable(table: TableDefinition) {
        table.column(Columns.id.name, .integer).primaryKey().check { $0 == 1 }
        table.column(Columns.deviceID.name, .text).notNull()
        table.column(Columns.cursor.name, .text)
        table.column(Columns.browseCursor.name, .text)
        table.column(Columns.browseComplete.name, .boolean).notNull().defaults(to: false)
        table.column(Columns.browseEdge.name, .datetime)
        table.column(Columns.browseEdgeID.name, .text)
        table.column(Columns.generation.name, .integer).notNull()
        table.column(Columns.resetting.name, .boolean).notNull()
        table.column(Columns.airplaneMode.name, .boolean).notNull()
        table.column(Columns.phase.name, .text).notNull().check { ["idle", "syncing", "waiting_for_network", "retrying"].contains($0) }
        table.column(Columns.lastSyncedAt.name, .datetime)
        table.column(Columns.lastError.name, .text)
    }
}
