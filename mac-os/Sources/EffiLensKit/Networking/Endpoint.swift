import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE"
}

/// Which credential an endpoint requires. core-services has two disjoint
/// auth dependencies (verified in `app/core/auth.py`):
/// - `get_current_user` / `require_*_role` → portal JWT only.
/// - `get_current_agent_user` → agent opaque token only.
/// - `get_current_user_or_agent` → either (consent, projects).
public enum AuthRequirement: Sendable {
    case none
    case portal
    case agent
}

/// A typed description of one backend call. `Response` is the decoded body.
public struct Endpoint<Response: Decodable & Sendable>: Sendable {
    public var method: HTTPMethod
    /// Path relative to `/api/v1`, beginning with `/`.
    public var path: String
    public var query: [URLQueryItem]
    public var body: Data?
    public var auth: AuthRequirement
    /// Safe to retry automatically on transient failure (GETs and idempotent writes).
    public var idempotent: Bool
    public var extraHeaders: [String: String]

    public init(
        _ method: HTTPMethod,
        _ path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        auth: AuthRequirement = .portal,
        idempotent: Bool? = nil,
        extraHeaders: [String: String] = [:]
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.auth = auth
        self.idempotent = idempotent ?? (method == .get || method == .put || method == .delete)
        self.extraHeaders = extraHeaders
    }

    /// Convenience for JSON bodies encoded with the backend's snake_case encoder.
    public static func json<Body: Encodable>(
        _ method: HTTPMethod,
        _ path: String,
        body: Body,
        query: [URLQueryItem] = [],
        auth: AuthRequirement = .portal,
        idempotent: Bool? = nil
    ) throws -> Endpoint<Response> {
        let data = try JSONCoding.makeEncoder().encode(body)
        return Endpoint(method, path, query: query, body: data, auth: auth, idempotent: idempotent)
    }
}

/// Placeholder for endpoints that return 204 / an ignorable body.
public struct EmptyResponse: Decodable, Sendable {
    public init() {}
    public init(from decoder: Decoder) throws {}
}

/// Helpers for building query strings without stringly-typed repetition.
public extension Array where Element == URLQueryItem {
    mutating func add(_ name: String, _ value: String?) {
        if let value { append(URLQueryItem(name: name, value: value)) }
    }
    mutating func add(_ name: String, _ value: Int?) {
        if let value { append(URLQueryItem(name: name, value: String(value))) }
    }
    mutating func add(_ name: String, _ value: Bool?) {
        if let value { append(URLQueryItem(name: name, value: value ? "true" : "false")) }
    }
    mutating func add(_ name: String, _ value: UUID?) {
        if let value { append(URLQueryItem(name: name, value: value.uuidString.lowercased())) }
    }
    mutating func add(_ name: String, _ value: CalendarDate?) {
        if let value { append(URLQueryItem(name: name, value: value.description)) }
    }
}
