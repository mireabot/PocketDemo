import Foundation

public struct RecordingID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard value.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid recording ID")
        }
        rawValue = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct Recording: Codable, Sendable, Equatable, Identifiable {
    private enum CodingKeys: String, CodingKey {
        case id, title, summary, version, createdAt, updatedAt, updatedBy, segmentCount
    }

    public let id: RecordingID
    public let title: String
    public let summary: String
    public let version: Int64
    public let createdAt: Date
    public let updatedAt: Date
    public let updatedBy: String?
    public let segmentCount: Int

    public init(
        id: RecordingID,
        title: String,
        summary: String,
        version: Int64,
        createdAt: Date,
        updatedAt: Date,
        updatedBy: String?,
        segmentCount: Int
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
        self.segmentCount = segmentCount
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(RecordingID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decode(String.self, forKey: .summary)
        version = try container.decode(Int64.self, forKey: .version)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        updatedBy = try container.decodeIfPresent(String.self, forKey: .updatedBy)
        segmentCount = try container.decode(Int.self, forKey: .segmentCount)
        guard version > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: container,
                debugDescription: "Recording version must be positive"
            )
        }
        guard segmentCount >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .segmentCount,
                in: container,
                debugDescription: "Recording segment count must not be negative"
            )
        }
    }

    public func value(of field: EditableField) -> String {
        switch field {
        case .title: title
        case .summary: summary
        }
    }
}

public enum EditableField: String, Codable, Sendable, CaseIterable, Hashable {
    case title
    case summary

    public var maxLength: Int {
        switch self {
        case .title: 300
        case .summary: 20000
        }
    }

    public func validate(_ value: String) throws(IntentError) {
        if self == .title, value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw .blankTitle
        }
        if value.utf16.count > maxLength {
            throw .tooLong(self, max: maxLength)
        }
    }
}
