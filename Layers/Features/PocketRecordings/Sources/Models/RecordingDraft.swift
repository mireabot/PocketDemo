import Domain

struct RecordingDraft: Identifiable, Sendable {
    let id: RecordingID
    let original: RecordingDetail
    var title: String
    var summary: String
    var changes: [EditableField: String] {
        var changes: [EditableField: String] = [:]
        if title != original.title { changes[.title] = title }
        if summary != original.summary { changes[.summary] = summary }
        return changes
    }

    init(_ detail: RecordingDetail) {
        id = detail.id
        original = detail
        title = detail.title
        summary = detail.summary
    }
}
