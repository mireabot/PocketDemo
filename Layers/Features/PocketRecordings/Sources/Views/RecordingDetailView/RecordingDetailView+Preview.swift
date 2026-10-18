import Domain
import SwiftUI

#Preview("Transcript") {
    RecordingDetailPreview(detail: .demo)
}

#Preview("Title conflict") {
    RecordingDetailPreview(detail: .demoConflict)
}

#Preview("Title and summary conflicts") {
    RecordingDetailPreview(detail: .demoTwoConflicts)
}

#Preview("Offline") {
    RecordingDetailPreview(detail: .demoOffline)
}

private struct RecordingDetailPreview: View {
    let detail: RecordingDetail

    var body: some View {
        NavigationStack {
            RecordingDetailContent(
                detail: detail,
                onEdit: {},
                onDelete: {},
                onDiscardFailures: {},
                onRetryTranscript: {},
                onResolveField: { _, _ in },
                onResolveDelete: { _, _ in }
            )
        }
    }
}

private extension RecordingDetail {
    static let demoServer = Recording(
        id: RecordingID("rec_demo"),
        title: "Product sync with design",
        summary: "Walked through the new onboarding flow. Agreed to cut the second permission screen, keep the progress bar and test the shorter copy with five users next week.",
        version: 42,
        createdAt: Date().addingTimeInterval(-3 * 86400),
        updatedAt: Date().addingTimeInterval(-2 * 3600),
        updatedBy: "ios-demo-device",
        segmentCount: 6
    )

    static let demoTranscript = Transcript(segments: [
        .init(id: 0, startMs: 0, text: "Okay, let's start with onboarding. Everyone has seen the latest build?"),
        .init(id: 1, startMs: 6400, text: "Yes. The second permission screen feels like too much right after sign up."),
        .init(id: 2, startMs: 14200, text: "Agreed. We can ask for notifications later, when the first recording finishes."),
        .init(id: 3, startMs: 23800, text: "Do we keep the progress bar? People liked knowing how many steps were left."),
        .init(id: 4, startMs: 31500, text: "Keep it. Let's also try the shorter welcome copy."),
        .init(id: 5, startMs: 40100, text: "I'll set up five user sessions next week and share the notes."),
    ])

    static let demo = RecordingDetail(
        id: demoServer.id,
        title: demoServer.title,
        summary: demoServer.summary,
        createdAt: demoServer.createdAt,
        updatedAt: demoServer.updatedAt,
        updatedBy: demoServer.updatedBy,
        pendingFields: [],
        conflicts: [],
        transcript: .loaded(demoTranscript),
        failures: [],
        base: demoServer
    )

    static let demoConflict = RecordingDetail(
        id: demoServer.id,
        title: "Onboarding review: cut permissions",
        summary: demoServer.summary,
        createdAt: demoServer.createdAt,
        updatedAt: demoServer.updatedAt,
        updatedBy: "ios-other-device",
        pendingFields: [.title],
        conflicts: [.field(FieldConflict(
            recordingID: demoServer.id,
            field: .title,
            base: demoServer.title,
            mine: "Onboarding review: cut permissions",
            theirs: "Design sync: onboarding v2",
            changedBy: "ios-other-device",
            changedAt: Date().addingTimeInterval(-600)
        ))],
        transcript: .loaded(demoTranscript),
        failures: [],
        base: demoServer
    )

    static let demoTwoConflicts = RecordingDetail(
        id: demoServer.id,
        title: demoConflict.title,
        summary: "Ask for notification permissions after the first recording finishes.",
        createdAt: demoServer.createdAt,
        updatedAt: demoServer.updatedAt,
        updatedBy: "ios-other-device",
        pendingFields: [.title, .summary],
        conflicts: demoConflict.conflicts + [.field(FieldConflict(
            recordingID: demoServer.id,
            field: .summary,
            base: demoServer.summary,
            mine: "Ask for notification permissions after the first recording finishes.",
            theirs: "Keep the permission screen and test shorter copy next week.",
            changedBy: "ios-other-device",
            changedAt: Date().addingTimeInterval(-600)
        ))],
        transcript: .loaded(demoTranscript),
        failures: [],
        base: demoServer
    )

    static let demoOffline = RecordingDetail(
        id: demoServer.id,
        title: demoServer.title,
        summary: "Edited offline: cut the second permission screen and test shorter copy.",
        createdAt: demoServer.createdAt,
        updatedAt: demoServer.updatedAt,
        updatedBy: demoServer.updatedBy,
        pendingFields: [.summary],
        conflicts: [],
        transcript: .waitingForNetwork,
        failures: [],
        base: demoServer
    )
}
