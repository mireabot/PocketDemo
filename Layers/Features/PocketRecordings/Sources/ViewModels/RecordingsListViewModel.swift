import Domain
import Foundation
import Observation

enum Loadable<Value> { case loading, loaded(Value) }

@MainActor @Observable
final class RecordingsListViewModel {
    private(set) var sections: Loadable<RecordingSections> = .loading
    private(set) var status: SyncStatus?
    private(set) var notices: [Notice] = []
    private(set) var isFetchingNextPage = false
    var errorMessage: String?
    @ObservationIgnored private let repository = RecordingsRepository()
    @ObservationIgnored private var lastPaginatedCount: Int?

    func observe() async {
        async let sections: Void = observeSections()
        async let status: Void = observeStatus()
        async let notices: Void = observeNotices()
        _ = await (sections, status, notices)
    }

    private func observeSections() async {
        do {
            for try await value in repository.sections() {
                sections = .loaded(value)
            }
        } catch {
            if !Task.isCancelled { errorMessage = "Couldn't read recordings from this device." }
        }
    }

    private func observeStatus() async {
        do {
            for try await value in repository.status() {
                status = value
            }
        } catch {
            if !Task.isCancelled { errorMessage = "Couldn't read sync status." }
        }
    }

    private func observeNotices() async {
        do {
            for try await value in repository.notices() {
                notices = value
            }
        } catch {
            if !Task.isCancelled { errorMessage = "Couldn't read notifications." }
        }
    }

    /// Asks for the next page when the first of the last 10 rows appears, once per loaded count.
    func handlePaginationIfNeeded(for row: RecordingRow) {
        guard case let .loaded(sections) = sections, sections.hasMore else { return }
        guard let trigger = sections.all.suffix(10).first, row.id == trigger.id else { return }
        guard lastPaginatedCount != sections.all.count else { return }
        lastPaginatedCount = sections.all.count
        Task { await fetchNextPage() }
    }

    private func fetchNextPage() async {
        guard !isFetchingNextPage else { return }
        isFetchingNextPage = true
        defer { isFetchingNextPage = false }
        await repository.loadNextPage()
        // No new rows means the page didn't arrive (offline or a server error), so the same row may ask again.
        if case let .loaded(sections) = sections, sections.all.count == lastPaginatedCount { lastPaginatedCount = nil }
    }

    func refresh() async { await repository.refresh() }
    func setAirplaneMode(_ on: Bool) async { await repository.setAirplaneMode(on) }
    func delete(_ id: RecordingID) async {
        do { try await repository.delete(id) } catch { errorMessage = RecordingsRepository.message(error) }
    }

    func dismissNotice(_ notice: Notice) async {
        do { try await repository.dismiss(notice) } catch { errorMessage = RecordingsRepository.message(error) }
    }
}
