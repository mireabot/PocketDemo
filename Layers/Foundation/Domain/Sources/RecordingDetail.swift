import Foundation

public struct RecordingDetail: Sendable, Equatable {
    public let id: RecordingID
    public let title: String
    public let summary: String
    public let createdAt: Date
    public let updatedAt: Date
    public let updatedBy: String?
    public let pendingFields: Set<EditableField>
    public let conflicts: [Conflict]
    public let transcript: TranscriptState
    public let failures: [FailedChange]
    public let base: Recording

    public init(
        id: RecordingID,
        title: String,
        summary: String,
        createdAt: Date,
        updatedAt: Date,
        updatedBy: String?,
        pendingFields: Set<EditableField>,
        conflicts: [Conflict],
        transcript: TranscriptState,
        failures: [FailedChange],
        base: Recording
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
        self.pendingFields = pendingFields
        self.conflicts = conflicts
        self.transcript = transcript
        self.failures = failures
        self.base = base
    }
}
