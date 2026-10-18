import Domain

struct RecordingSections: Sendable, Equatable {
    let needsAttention: [RecordingRow]
    let all: [RecordingRow]
    let hasMore: Bool
    var isEmpty: Bool { needsAttention.isEmpty && all.isEmpty }
}
