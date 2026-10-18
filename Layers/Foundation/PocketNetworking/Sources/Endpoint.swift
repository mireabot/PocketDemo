import Foundation

public protocol RestEndpoint: Sendable {
    associatedtype Response: Decodable & Sendable
    associatedtype Body: Encodable & Sendable = EmptyBody
    var path: String { get }
    var method: RestMethod { get }
    var queryItems: [URLQueryItem] { get }
    var headers: [String: String] { get }
    var body: Body? { get }
    var timeout: TimeInterval? { get }
}

public extension RestEndpoint {
    var queryItems: [URLQueryItem] { [] }
    var headers: [String: String] { [:] }
    var timeout: TimeInterval? { nil }
}

public extension RestEndpoint where Body == EmptyBody {
    var body: EmptyBody? { nil }
}

public struct EmptyBody: Encodable, Sendable {}
public struct EmptyResponse: Decodable, Sendable {
    public init() {}
}

public enum RestMethod: String, Sendable {
    case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE"
}

public protocol RequestAdapter: Sendable {
    func adapt(_ request: URLRequest) throws -> URLRequest
}

public struct StaticHeaders: RequestAdapter {
    private let values: [String: String]
    public init(_ values: [String: String]) { self.values = values }
    public func adapt(_ request: URLRequest) -> URLRequest {
        var request = request
        for (name, value) in values {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }
}

public enum RestClientError: Error, Sendable {
    case invalidURL
    case encoding(String)
    case decoding(String)
    case invalidResponse
    case http(HTTPFailure)
    case transport(URLError)
    case cancelled
    case other(String)

    public var isOffline: Bool {
        guard case let .transport(error) = self else { return false }
        return error.code == .notConnectedToInternet || error.code == .dataNotAllowed
    }
}

public struct HTTPFailure: Sendable {
    public let status: Int
    public let body: Data
    public let headers: [String: String]

    public func decode<Value: Decodable>(_ type: Value.Type) -> Value? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try? decoder.decode(type, from: body)
    }
}

public enum Connectivity: Sendable, Equatable {
    case online, airplaneMode, noNetwork
}
