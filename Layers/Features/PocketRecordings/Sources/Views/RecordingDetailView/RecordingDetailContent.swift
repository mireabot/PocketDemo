import Domain
import PocketUI
import SwiftUI

struct RecordingDetailContent: View {
    let detail: RecordingDetail
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onDiscardFailures: () -> Void
    let onRetryTranscript: () -> Void
    let onResolveField: (FieldConflict, FieldResolution) -> Void
    let onResolveDelete: (DeleteConflict, DeleteResolution) -> Void

    @ScaledMetric(relativeTo: .body) private var bodySize = 16

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if !fieldConflicts.isEmpty {
                    RecordingConflictReviewView(conflicts: fieldConflicts, onResolve: onResolveField)
                }
                ForEach(deleteConflicts, id: \.recordingID) { conflict in
                    RecordingDeleteConflictView(conflict: conflict) { onResolveDelete(conflict, $0) }
                }
                if !detail.failures.isEmpty {
                    RecordingFailuresView(failures: detail.failures, onDiscard: onDiscardFailures)
                }
                RecordingOverviewView(title: detail.title, summary: detail.summary, isPending: !detail.pendingFields.isEmpty)
                RecordingTranscriptView(state: detail.transcript, onRetry: onRetryTranscript)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .font(.system(size: bodySize))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(PocketPalette.screen)
        .navigationTitle(detail.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit", action: onEdit)
                    .disabled(!detail.conflicts.isEmpty)
            }
            ToolbarItem(placement: .bottomBar) {
                Button("Delete", role: .destructive, action: onDelete)
                    .tint(.red)
                    .disabled(!detail.conflicts.isEmpty)
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
        }
    }

    private var fieldConflicts: [FieldConflict] {
        detail.conflicts.compactMap { conflict in
            guard case let .field(value) = conflict else { return nil }
            return value
        }
    }

    private var deleteConflicts: [DeleteConflict] {
        detail.conflicts.compactMap { conflict in
            guard case let .delete(value) = conflict else { return nil }
            return value
        }
    }
}
