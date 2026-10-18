import Domain
import Foundation
import Observation

@MainActor @Observable
final class RecordingDetailViewModel {
    let id: RecordingID
    private(set) var detail: Loadable<RecordingDetail?> = .loading
    var draft: RecordingDraft?
    var errorMessage: String?
    private(set) var saving = false
    @ObservationIgnored private let repository = RecordingsRepository()

    init(id: RecordingID) { self.id = id }
    func observe() async {
        do {
            try await repository.requestTranscript(id)
            for try await value in repository.recording(id) {
                detail = .loaded(value)
            }
        } catch {
            if !Task.isCancelled { errorMessage = "Couldn't read this recording from the device." }
        }
    }

    func beginEditing() {
        guard case let .loaded(detail?) = detail else { return }
        draft = RecordingDraft(detail)
    }

    func save(_ draft: RecordingDraft, simulating simulation: NetworkSimulation?) async -> Bool {
        guard !saving else { return false }
        saving = true
        defer { saving = false }
        do {
            try await repository.save(draft, simulating: simulation)
            return true
        } catch {
            errorMessage = RecordingsRepository.message(error)
            return false
        }
    }

    func delete() async {
        do { try await repository.delete(id) } catch { errorMessage = RecordingsRepository.message(error) }
    }

    func resolve(_ conflict: FieldConflict, _ resolution: FieldResolution) async {
        do { try await repository.resolve(conflict, resolution) } catch { errorMessage = RecordingsRepository.message(error) }
    }

    func resolve(_ conflict: DeleteConflict, _ resolution: DeleteResolution) async {
        do { try await repository.resolve(conflict, resolution) } catch { errorMessage = RecordingsRepository.message(error) }
    }

    func retryTranscript() async {
        do { try await repository.requestTranscript(id) } catch { errorMessage = RecordingsRepository.message(error) }
    }

    func discardFailedChanges() async {
        do { try await repository.discardFailedChanges(id) } catch { errorMessage = RecordingsRepository.message(error) }
    }
}
