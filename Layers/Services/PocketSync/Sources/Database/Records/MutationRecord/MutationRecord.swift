import Domain
import Foundation
import GRDB

public enum MutationStatus: String, Codable, Sendable, DatabaseValueConvertible {
    case pending, inflight, conflicted, failed
}

public enum MutationAction: String, Codable, Sendable, DatabaseValueConvertible {
    case edit, delete
}

public enum ConflictDecision: Sendable, Equatable {
    case drop, rebase, askUser
}

public struct MutationRecord: Codable, Sendable, Equatable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "mutations"
    public var sequence: Int64?
    public var id: String
    public var recordID: String
    public var action: MutationAction
    public var field: EditableField?
    public var oldValue: String?
    public var newValue: String?
    public var baseVersion: Int64
    public var status: MutationStatus
    public var createdAt: Date
    public var failureReason: String?

    public init(sequence: Int64? = nil, id: String = UUID().uuidString, recordID: String,
                action: MutationAction, field: EditableField? = nil, oldValue: String? = nil,
                newValue: String? = nil, baseVersion: Int64, status: MutationStatus = .pending,
                createdAt: Date = Date(), failureReason: String? = nil)
    {
        self.sequence = sequence
        self.id = id
        self.recordID = recordID
        self.action = action
        self.field = field
        self.oldValue = oldValue
        self.newValue = newValue
        self.baseVersion = baseVersion
        self.status = status
        self.createdAt = createdAt
        self.failureReason = failureReason
    }

    public enum CodingKeys: String, CodingKey {
        case sequence = "seq", id, action, field, status
        case recordID = "record_id", oldValue = "old_value", newValue = "new_value"
        case baseVersion = "base_version", createdAt = "created_at", failureReason = "failure_reason"
    }

    public enum Columns {
        public static let sequence = Column(CodingKeys.sequence)
        public static let id = Column(CodingKeys.id)
        public static let recordID = Column(CodingKeys.recordID)
        public static let action = Column(CodingKeys.action)
        public static let field = Column(CodingKeys.field)
        public static let oldValue = Column(CodingKeys.oldValue)
        public static let newValue = Column(CodingKeys.newValue)
        public static let baseVersion = Column(CodingKeys.baseVersion)
        public static let status = Column(CodingKeys.status)
        public static let createdAt = Column(CodingKeys.createdAt)
        public static let failureReason = Column(CodingKeys.failureReason)
    }
}
