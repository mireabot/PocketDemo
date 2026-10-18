import Foundation

public struct Notice: Identifiable, Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case deletedElsewhere(title: String)
    }

    public let id: String
    public let recordingID: RecordingID
    public let kind: Kind
    public let createdAt: Date

    public init(id: String, recordingID: RecordingID, kind: Kind, createdAt: Date) {
        self.id = id
        self.recordingID = recordingID
        self.kind = kind
        self.createdAt = createdAt
    }
}
