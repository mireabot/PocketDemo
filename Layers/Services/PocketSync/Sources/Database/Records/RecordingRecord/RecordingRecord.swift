import Domain
import Foundation
import GRDB

public struct RecordingRecord: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "recordings"
    public var id: String
    public var title: String
    public var summary: String
    public var version: Int64
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: String?
    public var segmentCount: Int
    public var seenGeneration: Int64
    public var locallyDeleted: Bool
    public var sync: RowSyncState

    public init(_ server: Recording, generation: Int64 = 0) {
        id = server.id.rawValue
        title = server.title
        summary = server.summary
        version = server.version
        createdAt = server.createdAt
        updatedAt = server.updatedAt
        updatedBy = server.updatedBy
        segmentCount = server.segmentCount
        seenGeneration = generation
        locallyDeleted = false
        sync = .synced
    }

    public enum CodingKeys: String, CodingKey {
        case id, title, summary, version, sync
        case createdAt = "created_at", updatedAt = "updated_at", updatedBy = "updated_by"
        case segmentCount = "segment_count", seenGeneration = "seen_generation", locallyDeleted = "locally_deleted"
    }

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let title = Column(CodingKeys.title)
        public static let summary = Column(CodingKeys.summary)
        public static let version = Column(CodingKeys.version)
        public static let createdAt = Column(CodingKeys.createdAt)
        public static let updatedAt = Column(CodingKeys.updatedAt)
        public static let updatedBy = Column(CodingKeys.updatedBy)
        public static let segmentCount = Column(CodingKeys.segmentCount)
        public static let seenGeneration = Column(CodingKeys.seenGeneration)
        public static let locallyDeleted = Column(CodingKeys.locallyDeleted)
        public static let sync = Column(CodingKeys.sync)
    }
}
