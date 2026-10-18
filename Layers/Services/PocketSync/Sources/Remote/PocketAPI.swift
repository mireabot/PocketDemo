import Domain
import Foundation
import PocketNetworking

struct WriteConflict: Sendable {
    let current: Recording
    let fields: Set<EditableField>
    let changedBy: String?
    let changedAt: Date
}

struct PocketAPI: Sendable {
    let client: RestClient

    enum SendOutcome: Sendable {
        case applied(Recording?), conflict(WriteConflict), gone, serverReset
        case rejected(String), offline, retryLater(String), cancelled
    }

    enum FeedOutcome: Sendable {
        case page(RecordingPage), cursorReset, offline, retryLater(String), cancelled
    }

    enum BrowseOutcome: Sendable {
        case page(BrowsePage), cursorReset, offline, retryLater(String), cancelled
    }

    enum DetailOutcome: Sendable {
        case found(Recording, [Transcript.Segment]), gone, offline, retryLater(String), cancelled
    }

    func send(_ mutation: MutationRecord, simulating simulation: NetworkSimulation? = nil) async -> SendOutcome {
        do {
            var headers = ["Idempotency-Key": mutation.id]
            if let simulation { headers["X-Sim-Fault"] = simulation.rawValue }
            let endpoint: APIEndpoint<WriteResponse, PatchBody>
            switch mutation.action {
            case .edit:
                guard let field = mutation.field, let value = mutation.newValue else { return .rejected("Invalid edit in mutations table") }
                endpoint = APIEndpoint(path: "/recordings/\(mutation.recordID)", method: .patch, headers: headers, body: PatchBody(baseVersion: mutation.baseVersion, field: field, value: value))
            case .delete:
                endpoint = APIEndpoint(path: "/recordings/\(mutation.recordID)", method: .delete, queryItems: [URLQueryItem(name: "baseVersion", value: String(mutation.baseVersion))], headers: headers)
            }
            let response = try await client.send(endpoint)
            switch response.recording {
            case let .live(recording):
                guard recording.id.rawValue == mutation.recordID, mutation.action == .edit else { return .retryLater("Unexpected write response") }
                return .applied(recording)
            case let .deleted(id):
                guard id.rawValue == mutation.recordID, mutation.action == .delete else { return .retryLater("Unexpected delete response") }
                return .applied(nil)
            }
        } catch {
            if error.isOffline { return .offline }
            if case .cancelled = error { return .cancelled }
            if case let .http(failure) = error {
                let response = failure.decode(APIErrorResponse.self)
                switch (failure.status, response?.error.code) {
                case (409, "version_conflict"):
                    guard let response, case let .live(current) = response.current,
                          current.id.rawValue == mutation.recordID,
                          let fields = response.conflicts, !fields.isEmpty else { return .retryLater("Malformed conflict response") }
                    return .conflict(WriteConflict(current: current, fields: Set(fields.map(\.field)), changedBy: fields.max(by: { $0.changedAt < $1.changedAt })?.changedBy, changedAt: fields.map(\.changedAt).max() ?? current.updatedAt))
                case (404, _), (410, "recording_deleted"): return .gone
                case (422, "base_version_ahead"): return .serverReset
                case (400 ..< 500, _): return .rejected(response?.error.message ?? "Request rejected (\(failure.status))")
                default: break
                }
            }
            return .retryLater(String(describing: error))
        }
    }

    func feed(cursor: String?, limit: Int) async -> FeedOutcome {
        do {
            var query = [URLQueryItem(name: "limit", value: String(limit))]
            if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
            let response = try await client.send(APIEndpoint<RecordingPage, EmptyBody>(path: "/recordings", method: .get, queryItems: query))
            guard !response.nextCursor.isEmpty else { return .retryLater("Missing feed cursor") }
            return .page(response)
        } catch {
            if error.isOffline { return .offline }
            if case .cancelled = error { return .cancelled }
            if case let .http(failure) = error, let code = failure.decode(APIErrorResponse.self)?.error.code,
               (failure.status == 410 && code == "cursor_reset") || (failure.status == 400 && code == "invalid_cursor") { return .cursorReset }
            return .retryLater(String(describing: error))
        }
    }

    func browse(after cursor: String?, limit: Int) async -> BrowseOutcome {
        do {
            var query = [URLQueryItem(name: "limit", value: String(limit))]
            if let cursor { query.append(URLQueryItem(name: "after", value: cursor)) }
            let response = try await client.send(APIEndpoint<BrowsePage, EmptyBody>(path: "/recordings/browse", method: .get, queryItems: query))
            guard !response.syncCursor.isEmpty, !response.hasMore || response.nextCursor != nil else { return .retryLater("Missing browse cursor") }
            return .page(response)
        } catch {
            if error.isOffline { return .offline }
            if case .cancelled = error { return .cancelled }
            if case let .http(failure) = error, let code = failure.decode(APIErrorResponse.self)?.error.code,
               (failure.status == 410 && code == "cursor_reset") || (failure.status == 400 && code == "invalid_cursor") { return .cursorReset }
            return .retryLater(String(describing: error))
        }
    }

    func detail(_ id: RecordingID) async -> DetailOutcome {
        do {
            let response = try await client.send(APIEndpoint<DetailResponse, EmptyBody>(path: "/recordings/\(id)", method: .get))
            guard response.recording.id == id else { return .retryLater("Wrong recording in detail response") }
            return .found(response.recording, response.transcript)
        } catch {
            if error.isOffline { return .offline }
            if case .cancelled = error { return .cancelled }
            if case let .http(failure) = error, failure.status == 404 || failure.status == 410 { return .gone }
            return .retryLater(String(describing: error))
        }
    }
}

private struct APIEndpoint<Response: Decodable & Sendable, Body: Encodable & Sendable>: RestEndpoint {
    var path: String
    var method: RestMethod
    var queryItems: [URLQueryItem] = []
    var headers: [String: String] = [:]
    var body: Body?
}

private struct PatchBody: Encodable, Sendable {
    let baseVersion: Int64
    let field: EditableField
    let value: String
    private enum CodingKeys: String, CodingKey { case baseVersion, title, summary }
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(baseVersion, forKey: .baseVersion)
        try container.encode(value, forKey: field == .title ? .title : .summary)
    }
}

enum RecordingChange: Decodable, Sendable {
    case live(Recording), deleted(RecordingID)
    private enum CodingKeys: String, CodingKey { case id, deleted }
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if try container.decode(Bool.self, forKey: .deleted) {
            self = try .deleted(container.decode(RecordingID.self, forKey: .id))
        } else { self = try .live(Recording(from: decoder)) }
    }
}

struct RecordingPage: Decodable, Sendable {
    let items: [RecordingChange]
    let nextCursor: String
    let hasMore: Bool
}

struct BrowsePage: Decodable, Sendable {
    let items: [Recording]
    let nextCursor: String?
    let hasMore: Bool
    let syncCursor: String
}

private struct WriteResponse: Decodable, Sendable { let recording: RecordingChange }
private struct DetailResponse: Decodable, Sendable {
    let recording: Recording
    let transcript: [Transcript.Segment]
    private enum CodingKeys: String, CodingKey { case transcript }
    init(from decoder: any Decoder) throws {
        recording = try Recording(from: decoder)
        transcript = try decoder.container(keyedBy: CodingKeys.self).decode([Transcript.Segment].self, forKey: .transcript)
    }
}

private struct APIErrorResponse: Decodable, Sendable {
    struct Detail: Decodable, Sendable { let code: String; let message: String }
    struct Field: Decodable, Sendable { let field: EditableField; let changedBy: String?; let changedAt: Date }
    let error: Detail
    let current: RecordingChange?
    let conflicts: [Field]?
}
