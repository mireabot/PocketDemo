import Foundation
import PocketNetworking
import Synchronization

enum NetworkingChecks {
    static func run() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NetworkingProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = RestClient(.init(
            baseURL: URL(string: "https://verification.invalid/api")!,
            adapters: [StaticHeaders(["Authorization": "Bearer verification", "X-Override": "adapter"]), NetworkingAdapter()],
            timeout: 19,
            session: session
        ))

        let writePath = "/api/write-\(UUID().uuidString)"
        var writeRequests = NetworkingProtocol.register(writePath, response: .reply(200, Data("{\"date\":1700000000123}".utf8))).makeAsyncIterator()
        let result = try await client.send(NetworkingWrite(path: String(writePath.dropFirst(4))))
        guard let write = await writeRequests.next() else { throw VerificationFailure(description: "Write request never started") }
        try check(write.request.url?.path == writePath && write.request.httpMethod == "PATCH", "REST client preserves the base path and endpoint method")
        let query = URLComponents(url: write.request.url!, resolvingAgainstBaseURL: false)?.queryItems
        try check(query == [URLQueryItem(name: "search", value: "a & b/+"), URLQueryItem(name: "page", value: "2")], "REST query values survive URL encoding")
        try check(write.request.value(forHTTPHeaderField: "Authorization") == "Bearer verification", "request adapter supplies authorization")
        try check(write.request.value(forHTTPHeaderField: "X-Adapted") == "Bearer verification", "request adapters run in configured order")
        try check(write.request.value(forHTTPHeaderField: "X-Override") == "endpoint", "per-call headers override adapter headers")
        try check(write.request.value(forHTTPHeaderField: "Accept") == "application/json" && write.request.value(forHTTPHeaderField: "Content-Type") == "application/json", "REST request advertises and sends JSON")
        try check(write.request.timeoutInterval == 7, "endpoint timeout overrides the client timeout")
        let json = try JSONSerialization.jsonObject(with: write.body) as? [String: Any]
        try check((json?["date"] as? NSNumber)?.doubleValue == 1_700_000_000_123 && json?["title"] as? String == "Updated title", "REST bodies encode dates as milliseconds")
        try check(result.date.timeIntervalSince1970 == 1_700_000_000.123, "REST responses decode dates as milliseconds")

        let emptyPath = "/api/empty-\(UUID().uuidString)"
        var emptyRequests = NetworkingProtocol.register(emptyPath, response: .reply(204, Data())).makeAsyncIterator()
        _ = try await client.send(NetworkingEmpty(path: String(emptyPath.dropFirst(4))))
        guard let empty = await emptyRequests.next() else { throw VerificationFailure(description: "Empty request never started") }
        try check(empty.request.timeoutInterval == 19, "endpoints inherit the configured timeout")
        try check(empty.body.isEmpty, "bodyless endpoints send no JSON body")
        try check(true, "204 succeeds without decoding an empty response body")

        let cancelledPath = "/api/cancelled-\(UUID().uuidString)"
        var cancelledRequests = NetworkingProtocol.register(cancelledPath, response: .hold).makeAsyncIterator()
        let cancelled = Task { try await client.send(NetworkingEmpty(path: String(cancelledPath.dropFirst(4)))) }
        guard await cancelledRequests.next() != nil else { throw VerificationFailure(description: "Cancellation request never started") }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            throw VerificationFailure(description: "Caller cancellation returned success")
        } catch RestClientError.cancelled {
            try check(true, "caller cancellation surfaces as cancelled")
        }

        let offlinePath = "/api/offline-\(UUID().uuidString)"
        var offlineRequests = NetworkingProtocol.register(offlinePath, response: .hold).makeAsyncIterator()
        let interrupted = Task { try await client.send(NetworkingEmpty(path: String(offlinePath.dropFirst(4)))) }
        guard await offlineRequests.next() != nil else { throw VerificationFailure(description: "Airplane request never started") }
        await client.verifyAirplaneRoundTrip()
        do {
            _ = try await interrupted.value
            throw VerificationFailure(description: "Airplane cancellation returned success")
        } catch let RestClientError.transport(error) {
            try check(error.code == .notConnectedToInternet, "airplane on then off keeps the active request's offline error")
        }
        try await check(client.currentConnectivity == .online, "airplane round trip leaves the client online")
    }
}

private extension RestClient {
    func verifyAirplaneRoundTrip() {
        // Both changes happen before the suspended send can resume on this actor.
        setOffline(true)
        setOffline(false)
    }
}

private struct NetworkingAdapter: RequestAdapter {
    func adapt(_ request: URLRequest) -> URLRequest {
        var request = request
        request.setValue(request.value(forHTTPHeaderField: "Authorization"), forHTTPHeaderField: "X-Adapted")
        return request
    }
}

private struct NetworkingWrite: RestEndpoint {
    struct Response: Decodable, Sendable { let date: Date }
    struct Body: Encodable, Sendable { let title: String; let date: Date }
    let path: String
    var method: RestMethod { .patch }
    var body: Body? { Body(title: "Updated title", date: Date(timeIntervalSince1970: 1_700_000_000.123)) }
    var headers: [String: String] { ["X-Override": "endpoint"] }
    var timeout: TimeInterval? { 7 }
    var queryItems: [URLQueryItem] { [URLQueryItem(name: "search", value: "a & b/+"), URLQueryItem(name: "page", value: "2")] }
}

private struct NetworkingEmpty: RestEndpoint {
    typealias Response = EmptyResponse
    let path: String
    var method: RestMethod { .delete }
}

// URLProtocol requires inherited unchecked conformance. Instances have no mutable
// state, and the shared response registry is accessed only through its Mutex.
private final class NetworkingProtocol: URLProtocol, @unchecked Sendable {
    enum Response: Sendable {
        case reply(Int, Data)
        case hold
    }

    struct ObservedRequest: Sendable {
        let request: URLRequest
        let body: Data
    }

    private struct Plan: Sendable {
        let response: Response
        let started: AsyncStream<ObservedRequest>.Continuation
    }

    private static let plans = Mutex<[String: Plan]>([:])

    static func register(_ path: String, response: Response) -> AsyncStream<ObservedRequest> {
        let (stream, continuation) = AsyncStream.makeStream(of: ObservedRequest.self, bufferingPolicy: .bufferingNewest(1))
        plans.withLock { $0[path] = Plan(response: response, started: continuation) }
        return stream
    }

    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let path = request.url?.path, let plan = Self.plans.withLock({ $0.removeValue(forKey: path) }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let body = try requestBody()
            plan.started.yield(ObservedRequest(request: request, body: body))
            plan.started.finish()
            switch plan.response {
            case let .reply(status, data):
                guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]) else {
                    throw URLError(.badServerResponse)
                }
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                if !data.isEmpty { client?.urlProtocol(self, didLoad: data) }
                client?.urlProtocolDidFinishLoading(self)
            case .hold:
                break
            }
        } catch {
            plan.started.finish()
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private func requestBody() throws -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count == 0 { return data }
            guard count > 0 else { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
            data.append(contentsOf: buffer.prefix(count))
        }
    }
}
