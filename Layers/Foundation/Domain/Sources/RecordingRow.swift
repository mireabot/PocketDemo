import Foundation

public struct RecordingRow: Identifiable, Sendable, Equatable {
    public let id: RecordingID
    public let title: String
    public let summary: String
    public let createdAt: Date
    public let updatedAt: Date
    public let sync: RowSyncState

    public init(
        id: RecordingID,
        title: String,
        summary: String,
        createdAt: Date,
        updatedAt: Date,
        sync: RowSyncState
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sync = sync
    }
}

public enum RowSyncState: String, Codable, Sendable, Equatable {
    case synced
    case pending
    case needsResolution
    case failed
}
