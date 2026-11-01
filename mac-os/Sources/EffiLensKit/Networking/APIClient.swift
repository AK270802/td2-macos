import Foundation

/// Supplies bearer credentials and recovers from 401s. Implemented by
/// `SessionManager`; abstracted so `APIClient` can be tested in isolation.
public protocol CredentialProvider: Sendable {
    /// Current bearer token for the requirement, or nil if signed out.
    func bearerToken(for requirement: AuthRequirement) async -> String?
    /// Called after a 401. Returns true if credentials were refreshed and the
    /// request should be retried once. Must be single-flight internally.
    func refreshAfterUnauthorized(for requirement: AuthRequirement, failedToken: String) async -> Bool
}

/// Abstraction over URLSession for testability.
public protocol HTTPTransport: Sendable {
    func perform(_ request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {
    // Explicit witness: Darwin's `data(for:delegate:)` has a defaulted extra
    // parameter, which cannot satisfy a protocol requirement by itself.
    public func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}

/// Thin async/await HTTP client for core-services `/api/v1`.
///
/// Responsibilities: request building, auth header injection, one-shot
/// refresh-and-retry on 401, bounded exponential backoff for transient
/// failures on idempotent requests, status → `AppError` mapping, decoding.
/// It contains **no business logic**.
public final class APIClient: Sendable {
    public let configuration: AppConfiguration
    private let transport: HTTPTransport
    private let credentials: CredentialProvider?
    private let retry: RetryPolicy

    public init(
        configuration: AppConfiguration,
        transport: HTTPTransport = APIClient.makeDefaultSession(),
        credentials: CredentialProvider?,
        retry: RetryPolicy = .standard
    ) {
        self.configuration = configuration
        self.transport = transport
        self.credentials = credentials
        self.retry = retry
    }

    /// Ephemeral session: no disk cache, no automatic cookie handling (the
    /// refresh cookie is managed explicitly and kept in the Keychain).
    public static func makeDefaultSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }

    // MARK: - Public API

    public func send<R>(_ endpoint: Endpoint<R>) async throws -> R {
        let (data, _) = try await sendRaw(endpoint)
        if R.self == EmptyResponse.self, let empty = EmptyResponse() as? R { return empty }
        do {
            return try JSONCoding.makeDecoder().decode(R.self, from: data)
        } catch {
            Log.network.error("decode failed for \(endpoint.path, privacy: .public): \(String(describing: error), privacy: .private)")
            throw AppError.decoding(endpoint.path)
        }
    }

    /// Returns raw body + response; used for login (needs `Set-Cookie`) and downloads.
    public func sendRaw<R>(_ endpoint: Endpoint<R>) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0
        var didRefresh = false
        while true {
            try Task.checkCancellation()
            let token = await credentials?.bearerToken(for: endpoint.auth)
            if endpoint.auth != .none, token == nil { throw AppError.unauthenticated }
            let request = try makeRequest(endpoint, token: token)
            do {
                let (data, response) = try await perform(request)
                switch response.statusCode {
                case 200..<300:
                    return (data, response)
                case 401 where endpoint.auth != .none && !didRefresh:
                    didRefresh = true
                    if let token, await credentials?.refreshAfterUnauthorized(for: endpoint.auth, failedToken: token) == true {
                        continue
                    }
                    throw AppError.unauthenticated
                default:
                    throw Self.mapError(status: response.statusCode, data: data, response: response)
                }
            } catch let error as AppError {
                guard error.isTransient, endpoint.idempotent, attempt < retry.maxRetries else { throw error }
                let delay = retry.delay(forAttempt: attempt, error: error)
                attempt += 1
                Log.network.info("retrying \(endpoint.path, privacy: .public) in \(delay, privacy: .public)s (attempt \(attempt, privacy: .public))")
                try await Task.sleep(for: .seconds(delay))
            }
        }
    }

    // MARK: - Internals

    func makeRequest<R>(_ endpoint: Endpoint<R>, token: String?) throws -> URLRequest {
        var components = URLComponents(url: configuration.apiBaseURL, resolvingAgainstBaseURL: false)
        let base = components?.path ?? ""
        components?.path = base + endpoint.path
        if !endpoint.query.isEmpty { components?.queryItems = endpoint.query }
        guard let url = components?.url else { throw AppError.configuration("Invalid request URL.") }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("EffiLens-macOS/\(configuration.appVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue(configuration.appVersion, forHTTPHeaderField: "X-Agent-Version")
        request.setValue(TimeZone.current.identifier, forHTTPHeaderField: "X-Timezone")
        if let body = endpoint.body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        for (key, value) in endpoint.extraHeaders { request.setValue(value, forHTTPHeaderField: key) }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await transport.perform(request)
            guard let http = response as? HTTPURLResponse else { throw AppError.unknown("Non-HTTP response") }
            return (data, http)
        } catch let error as AppError {
            throw error
        } catch is CancellationError {
            throw AppError.cancelled
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw AppError.cancelled
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
                 .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed:
                throw AppError.offline
            default:
                throw AppError.unknown("URLError \(error.code.rawValue)")
            }
        }
    }

    /// Maps an HTTP failure to `AppError`, extracting FastAPI's `detail`.
    static func mapError(status: Int, data: Data, response: HTTPURLResponse) -> AppError {
        let detail = FastAPIErrorBody.detailMessage(from: data)
        switch status {
        case 400, 422: return .validation(detail ?? "The request was not valid.")
        case 401: return .unauthenticated
        case 403:
            if response.value(forHTTPHeaderField: "X-Password-Change-Required")?.lowercased() == "true" {
                return .passwordChangeRequired
            }
            return .forbidden(detail)
        case 404: return .notFound
        case 409: return .conflict(detail)
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            return .rateLimited(retryAfter: retryAfter)
        case 500...599: return .server(status: status)
        default: return .unknown("HTTP \(status)")
        }
    }
}

/// FastAPI error bodies: `{"detail": "msg"}` or `{"detail": [{"loc": [...], "msg": "..."}]}`.
enum FastAPIErrorBody {
    private struct StringDetail: Decodable { let detail: String }
    private struct ListDetail: Decodable {
        struct Item: Decodable { let msg: String }
        let detail: [Item]
    }

    static func detailMessage(from data: Data) -> String? {
        let decoder = JSONDecoder()
        if let body = try? decoder.decode(StringDetail.self, from: data) { return body.detail }
        if let body = try? decoder.decode(ListDetail.self, from: data), !body.detail.isEmpty {
            return body.detail.map(\.msg).joined(separator: "\n")
        }
        return nil
    }
}
