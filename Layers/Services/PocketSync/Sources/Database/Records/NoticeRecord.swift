import Domain
import Foundation
import GRDB

public struct NoticeRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "notices"
    public var id: String
    public var recordingID: String
    public var title: String
    public var createdAt: Date

    public init(id: String = UUID().uuidString, recordingID: String, title: String, createdAt: Date = Date()) {
        self.id = id
        self.recordingID = recordingID
        self.title = title
        self.createdAt = createdAt
    }

    public enum CodingKeys: String, CodingKey {
        case id, title, recordingID = "recording_id", createdAt = "created_at"
    }

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let recordingID = Column(CodingKeys.recordingID)
        public static let title = Column(CodingKeys.title)
        public static let createdAt = Column(CodingKeys.createdAt)
    }
}

public extension NoticeRecord {
    var notice: Notice {
        Notice(id: id, recordingID: RecordingID(recordingID), kind: .deletedElsewhere(title: title), createdAt: createdAt)
    }
}

extension NoticeRecord: MigratableTable {
    public static func createTable(table: TableDefinition) {
        table.column(Columns.id.name, .text).primaryKey()
        table.column(Columns.recordingID.name, .text).notNull()
        table.column(Columns.title.name, .text).notNull()
        table.column(Columns.createdAt.name, .datetime).notNull()
    }
}
