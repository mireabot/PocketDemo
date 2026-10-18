import Domain
import SwiftUI

struct RecordingDetailView: View {
    @State private var viewModel: RecordingDetailViewModel
    @Environment(\.dismiss) private var dismiss

    init(id: RecordingID) { _viewModel = State(initialValue: RecordingDetailViewModel(id: id)) }

    var body: some View {
        content
            .task { await viewModel.observe() }
            .sheet(item: $viewModel.draft) { draft in
                EditRecordingView(
                    draft: draft,
                    isSaving: viewModel.saving,
                    errorMessage: viewModel.errorMessage,
                    onCancel: { viewModel.errorMessage = nil },
                    onSave: { await viewModel.save($0, simulating: $1) }
                )
            }
            .alert("Couldn't save", isPresented: Binding(get: { viewModel.errorMessage != nil && viewModel.draft == nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: { Text(viewModel.errorMessage ?? "") }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.detail {
        case .loading: ProgressView()
        case .loaded(nil):
            ContentUnavailableView("Recording removed", systemImage: "trash")
                .onAppear { dismiss() }
        case let .loaded(detail?):
            RecordingDetailContent(
                detail: detail,
                onEdit: { viewModel.beginEditing() },
                onDelete: { Task { await viewModel.delete() } },
                onDiscardFailures: { Task { await viewModel.discardFailedChanges() } },
                onRetryTranscript: { Task { await viewModel.retryTranscript() } },
                onResolveField: { conflict, resolution in Task { await viewModel.resolve(conflict, resolution) } },
                onResolveDelete: { conflict, resolution in Task { await viewModel.resolve(conflict, resolution) } }
            )
        }
    }
}
