import Foundation

public struct Transcript: Sendable, Equatable {
    public struct Segment: Codable, Sendable, Equatable, Identifiable {
        private enum CodingKeys: String, CodingKey {
            case startMs, text
        }

        public let id: Int
        public let startMs: Int
        public let text: String

        public init(id: Int, startMs: Int, text: String) {
            self.id = id
            self.startMs = startMs
            self.text = text
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = decoder.codingPath.last?.intValue ?? 0
            startMs = try container.decode(Int.self, forKey: .startMs)
            text = try container.decode(String.self, forKey: .text)
        }
    }

    public let segments: [Segment]

    public init(segments: [Segment]) {
        self.segments = segments
    }
}

public enum TranscriptState: Sendable, Equatable {
    case loaded(Transcript)
    case loading
    case waitingForNetwork
    case failed
}
