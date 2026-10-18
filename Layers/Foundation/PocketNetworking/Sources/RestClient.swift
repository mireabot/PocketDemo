import Foundation
import Network

public actor RestClient {
    public struct Configuration: Sendable {
        public var baseURL: URL
        public var adapters: [any RequestAdapter]
        public var timeout: TimeInterval
        public var session: URLSession

        public init(baseURL: URL, adapters: [any RequestAdapter] = [], timeout: TimeInterval = 15, session: URLSession = .shared) {
            self.baseURL = baseURL
            self.adapters = adapters
            self.timeout = timeout
            self.session = session
        }
    }

    private struct Flight {
        let task: Task<(Data, URLResponse), any Error>
        var cancelledOffline = false
    }

    private let configuration: Configuration
    private let monitor: NWPathMonitor
    private var monitoring = false
    private var offline = false
    private var pathAvailable = true
    private var flights: [UUID: Flight] = [:]
    private var subscribers: [UUID: AsyncStream<Connectivity>.Continuation] = [:]

    public init(_ configuration: Configuration) {
        self.configuration = configuration
        monitor = NWPathMonitor()
    }

    deinit { monitor.cancel() }

    public var currentConnectivity: Connectivity {
        offline ? .airplaneMode : pathAvailable ? .online : .noNetwork
    }

    public func connectivityUpdates() -> AsyncStream<Connectivity> {
        startMonitoring()
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: Connectivity.self, bufferingPolicy: .bufferingNewest(1))
        subscribers[id] = continuation
        continuation.yield(currentConnectivity)
        continuation.onTermination = { [weak self] _ in Task { await self?.unsubscribe(id) } }
        return stream
    }

    public func setOffline(_ value: Bool) {
        guard offline != value else { return }
        offline = value
        if value {
            for id in Array(flights.keys) {
                flights[id]?.cancelledOffline = true
                flights[id]?.task.cancel()
            }
        }
        publish()
    }

    public func send<E: RestEndpoint>(_ endpoint: E) async throws(RestClientError) -> E.Response {
        guard !offline else { throw .transport(URLError(.notConnectedToInternet)) }
        let request = try buildRequest(endpoint)
        let id = UUID()
        let session = configuration.session
        let task = Task { try await session.data(for: request) }
        flights[id] = Flight(task: task)
        defer { flights[id] = nil }
        do {
            let (data, response) = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            if flights[id]?.cancelledOffline == true { throw RestClientError.transport(URLError(.notConnectedToInternet)) }
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else { throw RestClientError.invalidResponse }
            guard (200 ..< 300).contains(response.statusCode) else {
                let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, pair in
                    result[String(describing: pair.key)] = String(describing: pair.value)
                }
                throw RestClientError.http(HTTPFailure(status: response.statusCode, body: data, headers: headers))
            }
            if let empty = EmptyResponse() as? E.Response { return empty }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            do {
                return try decoder.decode(E.Response.self, from: data)
            } catch {
                throw RestClientError.decoding(String(describing: error))
            }
        } catch {
            if flights[id]?.cancelledOffline == true { throw .transport(URLError(.notConnectedToInternet)) }
            if let error = error as? RestClientError { throw error }
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw .cancelled }
            if let error = error as? URLError { throw .transport(error) }
            throw .other(String(describing: error))
        }
    }

    private func buildRequest(_ endpoint: some RestEndpoint) throws(RestClientError) -> URLRequest {
        guard var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false) else { throw .invalidURL }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + endpoint.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !components.path.hasPrefix("/") { components.path = "/" + components.path }
        components.queryItems = endpoint.queryItems.isEmpty ? nil : endpoint.queryItems
        guard let url = components.url else { throw .invalidURL }
        var request = URLRequest(url: url, timeoutInterval: endpoint.timeout ?? configuration.timeout)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = endpoint.body {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            do {
                request.httpBody = try encoder.encode(body)
            } catch {
                throw .encoding(String(describing: error))
            }
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        do {
            for adapter in configuration.adapters {
                request = try adapter.adapt(request)
            }
        } catch {
            throw .other(String(describing: error))
        }
        for (name, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }

    private func startMonitoring() {
        guard !monitoring else { return }
        monitoring = true
        monitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { await self?.pathChanged(available) }
        }
        monitor.start(queue: .global(qos: .utility))
    }

    private func pathChanged(_ available: Bool) {
        pathAvailable = available
        publish()
    }

    private func publish() {
        for continuation in subscribers.values {
            continuation.yield(currentConnectivity)
        }
    }

    private func unsubscribe(_ id: UUID) { subscribers[id] = nil }
}
