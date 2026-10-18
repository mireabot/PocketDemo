import Foundation

public enum IntentError: Error, Sendable, Equatable {
    case recordingNotFound
    case recordingDeleted
    case blankTitle
    case tooLong(EditableField, max: Int)
    case unresolvedConflict(EditableField)
    case storageFailed(String)
    case conflictNeedsResolution
}

public enum StoreError: Error, Sendable {
    case databaseUnavailable(String)
}

public struct FailedChange: Identifiable, Sendable, Equatable {
    public let id: String
    public let message: String

    public init(id: String, message: String) {
        self.id = id
        self.message = message
    }
}
