import Domain
import Foundation
import GRDB

public extension TranscriptRecord {
    /// Experimental limit for cached transcript text. 30 MB is a starting number, not a measured one.
    static let cacheLimitBytes = 30 * 1024 * 1024

    static var wanted: QueryInterfaceRequest<Self> { filter(Columns.state == State.wanted.rawValue).order(Columns.recordingID) }

    /// Opening a recording asks for its transcript and marks it as recently used.
    static func request(_ id: RecordingID, in db: Database) throws {
        guard try RecordingRecord.fetchOne(db, key: id.rawValue) != nil else { return }
        guard var stored = try fetchOne(db, key: id.rawValue) else {
            try TranscriptRecord(recordingID: id.rawValue).insert(db)
            return
        }
        if stored.state == .failed { stored.state = .wanted }
        stored.openedAt = Date()
        try stored.update(db)
    }

    static func store(_ id: RecordingID, segments: [Transcript.Segment], limit: Int = cacheLimitBytes, in db: Database) throws {
        guard try RecordingRecord.fetchOne(db, key: id.rawValue) != nil else { return }
        let byteCount = try JSONEncoder().encode(segments).count
        try TranscriptRecord(recordingID: id.rawValue, state: .cached, segments: segments, fetchedAt: Date(), byteCount: byteCount).save(db)
        try evict(keeping: id, limit: limit, in: db)
    }

    /// Drops the least recently opened transcripts until the cache fits. The one just stored always stays,
    /// and an evicted transcript is fetched again the next time its recording is opened.
    static func evict(keeping id: RecordingID, limit: Int, in db: Database) throws {
        let cached = filter(Columns.state == State.cached.rawValue)
        var total = try cached.select(sum(Columns.byteCount), as: Int.self).fetchOne(db) ?? 0
        guard total > limit else { return }
        let oldest = try cached.filter(Columns.recordingID != id.rawValue)
            .order(Columns.openedAt, Columns.recordingID).fetchAll(db)
        for transcript in oldest where total > limit {
            try transcript.delete(db)
            total -= transcript.byteCount
        }
    }

    static func invalidate(in db: Database) throws {
        for var transcript in try fetchAll(db) {
            transcript.state = .wanted
            transcript.segments = nil
            transcript.fetchedAt = nil
            transcript.byteCount = 0
            try transcript.update(db)
        }
    }
}
