import Domain
import Foundation
import GRDB

public extension RecordingRecord {
    var recording: Recording {
        Recording(id: RecordingID(id), title: title, summary: summary, version: version,
                  createdAt: createdAt, updatedAt: updatedAt, updatedBy: updatedBy, segmentCount: segmentCount)
    }

    func row(in db: Database) throws -> RecordingRow {
        let shown = try displayedValues(MutationRecord.live(RecordingID(id), in: db))
        return RecordingRow(id: RecordingID(id), title: shown.title, summary: shown.summary, createdAt: createdAt, updatedAt: updatedAt, sync: sync)
    }

    private func displayedValues(_ mutations: [MutationRecord]) -> (title: String, summary: String) {
        var title = title
        var summary = summary
        for mutation in mutations where mutation.action == .edit {
            guard let value = mutation.newValue else { continue }
            switch mutation.field {
            case .title: title = value
            case .summary: summary = value
            case nil: break
            }
        }
        return (title, summary)
    }

    static var visible: QueryInterfaceRequest<Self> { filter(Columns.locallyDeleted == false) }

    static func detail(_ id: RecordingID, in db: Database) throws -> RecordingDetail? {
        guard let record = try fetchOne(db, key: id.rawValue), !record.locallyDeleted else { return nil }
        let mutations = try MutationRecord.live(id, in: db)
        let shown = record.displayedValues(mutations)
        var conflicts: [Conflict] = []
        var conflictedFields: Set<EditableField> = []
        for mutation in mutations where mutation.status == .conflicted {
            guard let conflict = try ConflictRecord.fetchOne(db, key: mutation.id) else { continue }
            switch mutation.action {
            case .edit:
                guard let field = mutation.field, conflictedFields.insert(field).inserted else { continue }
                conflicts.append(.field(FieldConflict(recordingID: id, field: field, base: mutation.oldValue ?? "",
                                                      mine: field == .title ? shown.title : shown.summary,
                                                      theirs: field == .title ? record.title : record.summary,
                                                      changedBy: conflict.changedBy, changedAt: conflict.changedAt)))
            case .delete:
                conflicts.append(.delete(DeleteConflict(recordingID: id, theirTitle: record.title,
                                                        theirSummary: record.summary, changedFields: conflict.changedFields,
                                                        changedBy: conflict.changedBy, changedAt: conflict.changedAt)))
            }
        }
        let state = try SyncStateRecord.load(in: db)
        let transcript = try TranscriptRecord.fetchOne(db, key: id.rawValue)
        let transcriptState: TranscriptState = if let transcript, transcript.state == .cached, let segments = transcript.segments {
            .loaded(Transcript(segments: segments))
        } else if transcript?.state == .failed {
            .failed
        } else {
            state.airplaneMode || state.phase == .waitingForNetwork ? .waitingForNetwork : .loading
        }
        let failures = try MutationRecord.filter(MutationRecord.Columns.recordID == id.rawValue)
            .filter(MutationRecord.Columns.status == MutationStatus.failed.rawValue)
            .order(MutationRecord.Columns.sequence).fetchAll(db)
            .map { FailedChange(id: $0.id, message: $0.failureReason ?? "Change rejected") }
        return RecordingDetail(id: id, title: shown.title, summary: shown.summary, createdAt: record.createdAt,
                               updatedAt: record.updatedAt, updatedBy: record.updatedBy,
                               pendingFields: Set(mutations.compactMap(\.field)), conflicts: conflicts,
                               transcript: transcriptState, failures: failures, base: record.recording)
    }
}
