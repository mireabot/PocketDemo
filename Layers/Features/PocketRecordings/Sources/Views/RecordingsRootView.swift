import Domain
import PocketUI
import SwiftUI

public struct RecordingsRootView: View {
    @State private var viewModel = RecordingsListViewModel()
    @State private var path: [RecordingID] = []
    public init() {}

    public var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if let notice = viewModel.notices.first {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recording removed").font(.headline)
                            if case let .deletedElsewhere(title) = notice.kind {
                                Text("\"\(title)\" was deleted on another device. Your unsynced changes were discarded.")
                            }
                            Button("Dismiss") { Task { await viewModel.dismissNotice(notice) } }
                        }
                    }
                    if case let .loaded(sections) = viewModel.sections {
                        if !sections.needsAttention.isEmpty {
                            Text("Needs attention").font(.headline)
                            rows(sections.needsAttention)
                        }
                        rows(sections.all) { viewModel.handlePaginationIfNeeded(for: $0) }
                        pageFooter(sections)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(PocketPalette.screen)
            .overlay { emptyState }
            .refreshable { await viewModel.refresh() }
            .navigationTitle("Recordings")
            .navigationDestination(for: RecordingID.self) { RecordingDetailView(id: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    let on = viewModel.status?.isAirplaneModeOn ?? false
                    Button {
                        Task { await viewModel.setAirplaneMode(!on) }
                    } label: {
                        Image(systemName: on ? "airplane.circle.fill" : "airplane.circle")
                    }
                }
                if let status = viewModel.status {
                    ToolbarItem(placement: .bottomBar) {
                        SyncStatusView(status: status)
                    }
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                }
            }
            .alert("Couldn't save", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: { Text(viewModel.errorMessage ?? "") }
        }
        .task { await viewModel.observe() }
    }

    private func rows(_ rows: [RecordingRow], onAppear: @escaping (RecordingRow) -> Void = { _ in }) -> some View {
        ForEach(rows) { row in
            Button {
                path.append(row.id)
            } label: {
                RecordingCard(title: row.title, summary: row.summary, updatedAt: row.updatedAt, status: cardStatus(row.sync))
            }
            .buttonStyle(.plain)
            .onAppear { onAppear(row) }
            .contextMenu {
                if row.sync != .needsResolution {
                    Button("Delete", role: .destructive) { Task { await viewModel.delete(row.id) } }
                }
            }
        }
    }

    @ViewBuilder private func pageFooter(_ sections: RecordingSections) -> some View {
        if viewModel.isFetchingNextPage {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        } else if sections.hasMore, !sections.isEmpty, isOffline {
            Text("Offline. Showing saved recordings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
    }

    private var isOffline: Bool {
        guard let status = viewModel.status else { return false }
        if status.isAirplaneModeOn { return true }
        if case .waitingForNetwork = status.phase { return true }
        return false
    }

    private func cardStatus(_ state: RowSyncState) -> RecordingCard.Tag? {
        switch state {
        case .synced: nil
        case .pending: RecordingCard.Tag(title: "Waiting to sync", systemImage: "arrow.triangle.2.circlepath")
        case .needsResolution: RecordingCard.Tag(title: "Needs resolution", systemImage: "exclamationmark.triangle")
        case .failed: RecordingCard.Tag(title: "Change failed", systemImage: "exclamationmark.circle")
        }
    }

    @ViewBuilder private var emptyState: some View {
        switch viewModel.sections {
        case .loading: ProgressView()
        case let .loaded(sections) where sections.isEmpty && viewModel.notices.isEmpty:
            ContentUnavailableView("No recordings", systemImage: "waveform", description: Text("Pull down to sync with the server."))
                .allowsHitTesting(false)
        case .loaded: EmptyView()
        }
    }
}

private struct SyncStatusView: View {
    let status: SyncStatus
    @ScaledMetric(relativeTo: .footnote) private var phaseSize = 14
    @ScaledMetric(relativeTo: .caption) private var countSize = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(phase)
                .font(.system(size: phaseSize))
            if status.pendingCount > 0 || status.conflictCount > 0 || status.failedCount > 0 {
                HStack(spacing: 8) {
                    if status.pendingCount > 0 { Text("\(status.pendingCount) pending") }
                    if status.conflictCount > 0 { Text("\(status.conflictCount) to resolve").foregroundStyle(.orange) }
                    if status.failedCount > 0 { Text("\(status.failedCount) failed").foregroundStyle(.red) }
                }
                .font(.system(size: countSize))
                .foregroundStyle(.secondary)
            }
        }
        .fixedSize()
        .transition(.blurReplace)
        .animation(.snappy(duration: 0.3), value: status)
        .padding(.horizontal, 8)
    }

    private var phase: String {
        if status.isAirplaneModeOn { return "Airplane mode" }
        return switch status.phase {
        case let .idle(last?): "Synced \(last.formatted(.relative(presentation: .named)))"
        case .idle(nil): "Not synced yet"
        case .syncing: "Syncing…"
        case .waitingForNetwork: "Offline"
        case .retrying: "Connection interrupted. Retrying…"
        }
    }
}
