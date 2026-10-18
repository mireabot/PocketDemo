import Foundation

public enum Conflict: Sendable, Equatable, Identifiable {
    case field(FieldConflict)
    case delete(DeleteConflict)

    public var id: String {
        switch self {
        case let .field(conflict): "\(conflict.recordingID).\(conflict.field.rawValue)"
        case let .delete(conflict): "\(conflict.recordingID).delete"
        }
    }
}

public struct FieldConflict: Sendable, Equatable {
    public let recordingID: RecordingID
    public let field: EditableField
    public let base: String
    public let mine: String
    public let theirs: String
    public let changedBy: String?
    public let changedAt: Date

    public init(
        recordingID: RecordingID,
        field: EditableField,
        base: String,
        mine: String,
        theirs: String,
        changedBy: String?,
        changedAt: Date
    ) {
        self.recordingID = recordingID
        self.field = field
        self.base = base
        self.mine = mine
        self.theirs = theirs
        self.changedBy = changedBy
        self.changedAt = changedAt
    }
}

public enum FieldResolution: Sendable, Equatable {
    case keepMine
    case keepTheirs
    case use(String)
}

public struct DeleteConflict: Sendable, Equatable {
    public let recordingID: RecordingID
    public let theirTitle: String
    public let theirSummary: String
    public let changedFields: Set<EditableField>
    public let changedBy: String?
    public let changedAt: Date

    public init(
        recordingID: RecordingID,
        theirTitle: String,
        theirSummary: String,
        changedFields: Set<EditableField>,
        changedBy: String?,
        changedAt: Date
    ) {
        self.recordingID = recordingID
        self.theirTitle = theirTitle
        self.theirSummary = theirSummary
        self.changedFields = changedFields
        self.changedBy = changedBy
        self.changedAt = changedAt
    }
}

public enum DeleteResolution: Sendable, Equatable {
    case deleteAnyway
    case keepRecording
}
