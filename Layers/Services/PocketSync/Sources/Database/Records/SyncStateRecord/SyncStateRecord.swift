import Domain
import Foundation
import GRDB

public struct SyncStateRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "sync_state"
    public enum Phase: String, Codable, Sendable, DatabaseValueConvertible {
        case idle, syncing, waitingForNetwork = "waiting_for_network", retrying
    }

    public var id: Int
    public var deviceID: String
    public var cursor: String?
    public var browseCursor: String?
    public var browseComplete: Bool
    public var browseEdge: Date?
    public var browseEdgeID: String?
    public var generation: Int64
    public var resetting: Bool
    public var airplaneMode: Bool
    public var phase: Phase
    public var lastSyncedAt: Date?
    public var lastError: String?

    public init(id: Int = 1, deviceID: String = "ios-" + UUID().uuidString.lowercased(), cursor: String? = nil,
                browseCursor: String? = nil, browseComplete: Bool = false, browseEdge: Date? = nil, browseEdgeID: String? = nil,
                generation: Int64 = 0, resetting: Bool = false,
                airplaneMode: Bool = false, phase: Phase = .idle, lastSyncedAt: Date? = nil, lastError: String? = nil)
    {
        self.id = id
        self.deviceID = deviceID
        self.cursor = cursor
        self.browseCursor = browseCursor
        self.browseComplete = browseComplete
        self.browseEdge = browseEdge
        self.browseEdgeID = browseEdgeID
        self.generation = generation
        self.resetting = resetting
        self.airplaneMode = airplaneMode
        self.phase = phase
        self.lastSyncedAt = lastSyncedAt
        self.lastError = lastError
    }

    public enum CodingKeys: String, CodingKey {
        case id, cursor, generation, resetting, phase
        case deviceID = "device_id", airplaneMode = "airplane_mode"
        case browseCursor = "browse_cursor", browseComplete = "browse_complete"
        case browseEdge = "browse_edge", browseEdgeID = "browse_edge_id"
        case lastSyncedAt = "last_synced_at", lastError = "last_error"
    }

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let deviceID = Column(CodingKeys.deviceID)
        public static let cursor = Column(CodingKeys.cursor)
        public static let browseCursor = Column(CodingKeys.browseCursor)
        public static let browseComplete = Column(CodingKeys.browseComplete)
        public static let browseEdge = Column(CodingKeys.browseEdge)
        public static let browseEdgeID = Column(CodingKeys.browseEdgeID)
        public static let generation = Column(CodingKeys.generation)
        public static let resetting = Column(CodingKeys.resetting)
        public static let airplaneMode = Column(CodingKeys.airplaneMode)
        public static let phase = Column(CodingKeys.phase)
        public static let lastSyncedAt = Column(CodingKeys.lastSyncedAt)
        public static let lastError = Column(CodingKeys.lastError)
    }
}
