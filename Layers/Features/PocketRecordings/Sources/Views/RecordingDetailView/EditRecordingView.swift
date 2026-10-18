import Domain
import PocketUI
import SwiftUI

struct EditRecordingView: View {
    @State private var draft: RecordingDraft
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var bodySize = 16
    @ScaledMetric(relativeTo: .footnote) private var labelSize = 14

    let isSaving: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onSave: @MainActor (RecordingDraft, NetworkSimulation?) async -> Bool

    init(draft: RecordingDraft, isSaving: Bool, errorMessage: String?, onCancel: @escaping () -> Void,
         onSave: @escaping @MainActor (RecordingDraft, NetworkSimulation?) async -> Bool)
    {
        _draft = State(initialValue: draft)
        self.isSaving = isSaving
        self.errorMessage = errorMessage
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 12) {
                        label("Title")
                        TextField("Title", text: $draft.title, axis: .vertical)
                            .padding(16)
                            .background(PocketPalette.surface, in: .rect(cornerRadius: 24))
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        label("Summary")
                        TextField("Summary", text: $draft.summary, axis: .vertical)
                            .padding(16)
                            .background(PocketPalette.surface, in: .rect(cornerRadius: 24))
                    }
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                }
                .font(.system(size: bodySize))
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .background(PocketPalette.screen)
            .navigationTitle("Edit recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Menu("Save") {
                        Button("Save") { save(nil) }
                        Button("Save on a slow network") { save(.slow) }
                        Button("Save, server applies it, reply lost") { save(.lostReply) }
                        Button("Save, request never reaches the server") { save(.neverSent) }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func save(_ simulation: NetworkSimulation?) {
        Task { if await onSave(draft, simulation) { dismiss() } }
    }

    private func label(_ title: String) -> some View {
        Text(title)
            .font(.system(size: labelSize, weight: .medium))
            .foregroundStyle(.secondary)
    }
}
