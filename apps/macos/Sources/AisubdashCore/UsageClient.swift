import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol UsageTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

private final class RedirectBlockingDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

final class URLSessionUsageTransport: UsageTransport, @unchecked Sendable {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 120

        self.session = URLSession(
            configuration: configuration,
            delegate: RedirectBlockingDelegate(),
            delegateQueue: nil
        )
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw UsageClientError.invalidResponse
        }
        return (data, response)
    }
}

public struct UsageClient: Sendable {
    private static let getTimeoutSeconds: TimeInterval = 12
    private static let refreshTimeoutSeconds: TimeInterval = 120
    private static let defaultTransport = URLSessionUsageTransport()

    private let transport: any UsageTransport

    public init() {
        self.transport = Self.defaultTransport
    }

    init(transport: any UsageTransport) {
        self.transport = transport
    }

    public func load(_ endpoint: UsageEndpoint) async throws -> UsageDashboard {
        guard let providersURL = URL(string: "/api/providers", relativeTo: endpoint.origin)?.absoluteURL,
              let snapshotsURL = URL(string: "/api/usage/latest-snapshots", relativeTo: endpoint.origin)?.absoluteURL
        else {
            throw UsageClientError.invalidResponse
        }

        let providersRequest = makeRequest(url: providersURL, method: "GET", timeout: Self.getTimeoutSeconds)
        let snapshotsRequest = makeRequest(url: snapshotsURL, method: "GET", timeout: Self.getTimeoutSeconds)

        async let providersResponse = perform(providersRequest)
        async let snapshotsResponse = perform(snapshotsRequest)

        let (providersData, snapshotsData) = try await (providersResponse, snapshotsResponse)
        return try UsageContractDecoder.decode(providersData: providersData, snapshotsData: snapshotsData)
    }

    public func refreshLocal() async throws -> Int {
        guard let refreshURL = URL(string: "/api/providers/refresh", relativeTo: UsageEndpoint.local.origin)?.absoluteURL else {
            throw UsageClientError.invalidResponse
        }

        let request = makeRequest(url: refreshURL, method: "POST", timeout: Self.refreshTimeoutSeconds)
        let data = try await perform(request)
        return try UsageContractDecoder.decodeRefreshFailureCount(data: data)
    }

    private func makeRequest(url: URL, method: String, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = method
        request.httpShouldHandleCookies = false
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as UsageClientError {
            throw error
        } catch {
            throw UsageClientError.networkError
        }

        guard (200..<300).contains(response.statusCode) else {
            throw UsageClientError.httpError(statusCode: response.statusCode)
        }
        return data
    }
}
