import Foundation

/// Bounded exponential backoff with jitter for interactive UI requests.
///
/// This is deliberately short (seconds): background event sync uses the Rust
/// agent's own queue backoff (1 → 2 → 4 … ≤ 30 min, `common::db::sync_queue`),
/// which is not duplicated here.
public struct RetryPolicy: Sendable {
    public var maxRetries: Int
    public var baseDelay: TimeInterval
    public var maxDelay: TimeInterval

    public static let standard = RetryPolicy(maxRetries: 2, baseDelay: 0.8, maxDelay: 6)
    public static let none = RetryPolicy(maxRetries: 0, baseDelay: 0, maxDelay: 0)

    public init(maxRetries: Int, baseDelay: TimeInterval, maxDelay: TimeInterval) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    public func delay(forAttempt attempt: Int, error: AppError) -> TimeInterval {
        if case .rateLimited(let retryAfter?) = error { return min(retryAfter, maxDelay * 5) }
        let exponential = baseDelay * pow(2, Double(attempt))
        let jitter = Double.random(in: 0...(baseDelay / 2))
        return min(exponential + jitter, maxDelay)
    }
}
