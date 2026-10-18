import GRDB

protocol MigratableTable: TableRecord, FetchableRecord, MutablePersistableRecord {
    static func createTable(table: TableDefinition)
}

let allTables: [any MigratableTable.Type] = [
    RecordingRecord.self,
    MutationRecord.self,
    ConflictRecord.self,
    TranscriptRecord.self,
    NoticeRecord.self,
    SyncStateRecord.self,
]

extension DatabaseMigrator {
    mutating func registerMigration(for table: any MigratableTable.Type) {
        registerMigration("create_\(table.databaseTableName)") { db in
            try db.create(table: table.databaseTableName) { table.createTable(table: $0) }
        }
    }
}
