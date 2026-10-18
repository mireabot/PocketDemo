import Domain
import Foundation
import GRDB

public struct TranscriptRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "transcripts"
    public enum State: String, Codable, Sendable, DatabaseValueConvertible { case wanted, cached, failed }
    public var recordingID: String
    public var state: State
    public var segments: [Transcript.Segment]?
    public var fetchedAt: Date?
    public var byteCount: Int
    public var openedAt: Date

    public init(recordingID: String, state: State = .wanted, segments: [Transcript.Segment]? = nil, fetchedAt: Date? = nil,
                byteCount: Int = 0, openedAt: Date = Date())
    {
        self.recordingID = recordingID
        self.state = state
        self.segments = segments
        self.fetchedAt = fetchedAt
        self.byteCount = byteCount
        self.openedAt = openedAt
    }

    public enum CodingKeys: String, CodingKey {
        case recordingID = "recording_id", state, segments, fetchedAt = "fetched_at"
        case byteCount = "byte_count", openedAt = "opened_at"
    }

    public enum Columns {
        public static let recordingID = Column(CodingKeys.recordingID)
        public static let state = Column(CodingKeys.state)
        public static let segments = Column(CodingKeys.segments)
        public static let fetchedAt = Column(CodingKeys.fetchedAt)
        public static let byteCount = Column(CodingKeys.byteCount)
        public static let openedAt = Column(CodingKeys.openedAt)
    }
}
