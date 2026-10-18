import Domain
import Foundation
import GRDB

public extension MutationRecord {
    static func validate(_ value: String, for field: EditableField) throws {
        try field.validate(value)
    }

    static func edit(_ id: RecordingID, field: EditableField, value: String,
                     basedOn: Recording? = nil, in db: Database) throws
    {
        try validate(value, for: field)
        guard let record = try RecordingRecord.fetchOne(db, key: id.rawValue) else { throw IntentError.recordingNotFound }
        guard !record.locallyDeleted else { throw IntentError.recordingDeleted }
        let mutations = try live(id, in: db)
        guard !mutations.contains(where: { $0.status == .conflicted }) else { throw IntentError.conflictNeedsResolution }
        let shown = mutations.last(where: { $0.action == .edit && $0.field == field })?.newValue
            ?? record.recording.value(of: field)
        guard shown != value else { return }
        let base = basedOn ?? record.recording
        let old = field == .title ? base.title : base.summary
        var mutation = MutationRecord(recordID: id.rawValue, action: .edit, field: field,
                                      oldValue: old, newValue: value, baseVersion: base.version)
        try mutation.insert(db)
        try RecordingRecord.reconcile(id, in: db)
    }

    static func delete(_ id: RecordingID, in db: Database) throws {
        guard let record = try RecordingRecord.fetchOne(db, key: id.rawValue) else { throw IntentError.recordingNotFound }
        let mutations = try live(id, in: db)
        guard !mutations.contains(where: { $0.status == .conflicted }) else { throw IntentError.conflictNeedsResolution }
        guard !record.locallyDeleted else { return }
        var mutation = MutationRecord(recordID: id.rawValue, action: .delete, baseVersion: record.version)
        try mutation.insert(db)
        try RecordingRecord.reconcile(id, in: db)
    }

    static func resolve(_ conflict: FieldConflict, with resolution: FieldResolution, in db: Database) throws {
        let id = conflict.recordingID
        guard let record = try RecordingRecord.fetchOne(db, key: id.rawValue) else { return }
        let rows = try live(id, in: db).filter { $0.field == conflict.field }
        guard rows.contains(where: { $0.status == .conflicted }), let first = rows.first else { return }
        guard !rows.contains(where: { $0.status == .inflight }) else { throw IntentError.conflictNeedsResolution }
        let target: String? = switch resolution {
        case .keepMine: rows.last?.newValue
        case .keepTheirs: nil
        case let .use(value): value
        }
        if let target { try validate(target, for: conflict.field) }
        let baseline = conflict.field == .title ? record.title : record.summary
        for row in rows {
            try remove(row, in: db)
        }
        if let target, target != baseline {
            var replacement = MutationRecord(sequence: first.sequence, recordID: id.rawValue, action: .edit,
                                             field: conflict.field, oldValue: baseline, newValue: target, baseVersion: record.version,
                                             createdAt: first.createdAt)
            try replacement.insert(db)
        }
        try RecordingRecord.reconcile(id, in: db)
    }

    static func resolve(_ conflict: DeleteConflict, with resolution: DeleteResolution, in db: Database) throws {
        let id = conflict.recordingID
        guard let record = try RecordingRecord.fetchOne(db, key: id.rawValue),
              let mutation = try live(id, in: db).first(where: { $0.action == .delete && $0.status == .conflicted }) else { return }
        try remove(mutation, in: db)
        if resolution == .deleteAnyway {
            var replacement = MutationRecord(sequence: mutation.sequence, recordID: id.rawValue,
                                             action: .delete, baseVersion: record.version, createdAt: mutation.createdAt)
            try replacement.insert(db)
        }
        try RecordingRecord.reconcile(id, in: db)
    }
}
