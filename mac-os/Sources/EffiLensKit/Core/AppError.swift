import Foundation

/// Every failure surfaced to view models is mapped onto this type so the UI
/// can render consistent, non-technical error states. Messages never contain
/// tokens, passwords or raw response bodies.
public enum AppError: Error, Sendable, Equatable {
    /// No network / host unreachable / timed out.
    case offline
    /// 401 that could not be recovered by refreshing — user must sign in again.
    case unauthenticated
    /// Backend demands a password change (403 + `X-Password-Change-Required`).
    case passwordChangeRequired
    /// 403 — the current role may not perform this action.
    case forbidden(String?)
    /// 404.
    case notFound
    /// 409 / optimistic-concurrency conflict (e.g. leave `client_updated_at`).
    case conflict(String?)
    /// 422 or 400 with the backend's `detail` message (safe to display).
    case validation(String)
    /// 429.
    case rateLimited(retryAfter: TimeInterval?)
    /// 5xx.
    case server(status: Int)
    /// Response could not be decoded into the expected schema.
    case decoding(String)
    /// Local agent (Rust daemon) is not reachable or rejected the request.
    case agentUnavailable(String)
    /// Misconfiguration (missing server URL, etc.).
    case configuration(String)
    case cancelled
    case unknown(String)

    /// Short, user-facing description.
    public var userMessage: String {
        switch self {
        case .offline:
            return "You're offline. EffiLens will keep tracking and sync when the connection returns."
        case .unauthenticated:
            return "Your session has expired. Please sign in again."
        case .passwordChangeRequired:
            return "Your organisation requires you to change your password before continuing."
        case .forbidden(let detail):
            return detail ?? "You don't have permission to do this."
        case .notFound:
            return "This item no longer exists."
        case .conflict(let detail):
            return detail ?? "This item was changed elsewhere. Refresh and try again."
        case .validation(let detail):
            return detail
        case .rateLimited:
            return "Too many requests. Please wait a moment and try again."
        case .server(let status):
            return "The EffiLens server had a problem (HTTP \(status)). Please try again shortly."
        case .decoding:
            return "EffiLens received data it didn't understand. Please update the app or contact support."
        case .agentUnavailable:
            return "The EffiLens tracking agent isn't running."
        case .configuration(let detail):
            return detail
        case .cancelled:
            return "Cancelled."
        case .unknown:
            return "Something went wrong. Please try again."
        }
    }

    /// Whether automatic retry (with backoff) is appropriate.
    public var isTransient: Bool {
        switch self {
        case .offline, .rateLimited, .server: return true
        default: return false
        }
    }
}
