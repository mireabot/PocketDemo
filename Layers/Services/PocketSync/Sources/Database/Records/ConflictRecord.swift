import Domain
import Foundation
import GRDB

public struct ConflictRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "conflicts"
    public var mutationID: String
    public var changedFields: Set<EditableField>
    public var changedBy: String?
    public var changedAt: Date
    public var detectedAt: Date

    public init(mutationID: String, changedFields: Set<EditableField>, changedBy: String?,
                changedAt: Date, detectedAt: Date = Date())
    {
        self.mutationID = mutationID
        self.changedFields = changedFields
        self.changedBy = changedBy
        self.changedAt = changedAt
        self.detectedAt = detectedAt
    }

    public enum CodingKeys: String, CodingKey {
        case mutationID = "mutation_id", changedFields = "changed_fields", changedBy = "changed_by"
        case changedAt = "changed_at", detectedAt = "detected_at"
    }

    public enum Columns {
        public static let mutationID = Column(CodingKeys.mutationID)
        public static let changedFields = Column(CodingKeys.changedFields)
        public static let changedBy = Column(CodingKeys.changedBy)
        public static let changedAt = Column(CodingKeys.changedAt)
        public static let detectedAt = Column(CodingKeys.detectedAt)
    }
}

extension ConflictRecord: MigratableTable {
    public static func createTable(table: TableDefinition) {
        table.column(Columns.mutationID.name, .text).primaryKey()
            .references(MutationRecord.databaseTableName, column: MutationRecord.Columns.id.name, onDelete: .cascade)
        table.column(Columns.changedFields.name, .text).notNull()
        table.column(Columns.changedBy.name, .text)
        table.column(Columns.changedAt.name, .datetime).notNull()
        table.column(Columns.detectedAt.name, .datetime).notNull()
    }
}
