import Foundation

/// Signed-in identity, resolved from `GET /users/me` after authentication.
public struct SessionIdentity: Sendable, Equatable {
    public let userId: UUID
    public let tenantId: UUID
    public let email: String
}

/// Session lifecycle events broadcast to the UI layer.
public enum SessionEvent: Sendable, Equatable {
    case signedIn(SessionIdentity)
    case signedOut
    /// Refresh failed — credentials were cleared; UI must return to sign-in.
    case expired
    case passwordChangeRequired
}

/// Owns both credentials the native app needs and keeps them fresh.
///
/// Verified backend facts (core-services/app/core/auth.py, api/v1/auth.py):
/// - Portal endpoints (leave, dashboard, reports, task-time, notifications…)
///   depend on `get_current_user` → **portal JWT only** (RS256, 15 min).
///   Its refresh token is the rotating HttpOnly cookie `wp_refresh_token`
///   (path `/`, 7 days) consumed by `POST /auth/refresh`.
/// - Agent endpoints (`/agent/*`, `/activity/batch`, `/screenshots/upload`)
///   depend on `get_current_agent_user` → **agent opaque token only** (90 days),
///   rotated by `POST /auth/agent/refresh`.
///
/// One sign-in screen performs both logins with the same credentials, so the
/// user signs in once and no backend change is required. The agent token is
/// handed to the Rust daemon over authenticated IPC (Milestone 3).
public actor SessionManager: CredentialProvider {
    private let http: APIClient            // unauthenticated client
    private let secrets: SecretStore
    private var portalAccessToken: String?
    private var portalAccessExpiry: Date?
    private var refreshTask: Task<Bool, Never>?
    private var agentRefreshTask: Task<Bool, Never>?
    private var eventContinuations: [UUID: AsyncStream<SessionEvent>.Continuation] = [:]

    public static let refreshCookieName = "wp_refresh_token"

    public init(configuration: AppConfiguration, secrets: SecretStore, transport: HTTPTransport = APIClient.makeDefaultSession()) {
        self.http = APIClient(configuration: configuration, transport: transport, credentials: nil, retry: .none)
        self.secrets = secrets
    }

    // MARK: - Events

    public func events() -> AsyncStream<SessionEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<SessionEvent>.makeStream(bufferingPolicy: .bufferingNewest(8))
        eventContinuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id) }
        }
        return stream
    }

    private func removeContinuation(_ id: UUID) { eventContinuations[id] = nil }

    private func emit(_ event: SessionEvent) {
        for continuation in eventContinuations.values { continuation.yield(event) }
    }

    // MARK: - Sign in / restore / sign out

    /// Signs in to both the portal and the agent API. Throws `AppError`.
    /// Credentials are never persisted; only the resulting tokens are.
    @discardableResult
    public func signIn(email: String, password: String) async throws -> AgentLoginResponse {
        let body = LoginRequest(email: email.trimmingCharacters(in: .whitespaces), password: password)

        // 1. Portal session (JWT + refresh cookie).
        let portalEndpoint = try Endpoint<TokenResponse>.json(.post, "/auth/login", body: body, auth: .none, idempotent: false)
        let (portalData, portalResponse) = try await http.sendRaw(portalEndpoint)
        let token = try decode(TokenResponse.self, portalData, path: "/auth/login")
        guard let refresh = Self.extractRefreshCookie(from: portalResponse) else {
            Log.auth.error("portal login succeeded but no refresh cookie was returned")
            throw AppError.unknown("Missing refresh cookie")
        }

        // 2. Agent device token. Note: the backend revokes the user's previous
        // agent device named "workpulse-agent" on every agent login.
        let agentEndpoint = try Endpoint<AgentLoginResponse>.json(.post, "/auth/agent/login", body: body, auth: .none, idempotent: false)
        let agent = try await http.send(agentEndpoint)

        try secrets.write(refresh, for: .portalRefreshToken)
        try secrets.write(agent.accessToken, for: .agentToken)
        try? secrets.write(body.email, for: .lastEmail)
        setPortalAccess(token)

        Log.auth.info("signed in")
        if agent.passwordChanged == false { emit(.passwordChangeRequired) }
        emit(.signedIn(SessionIdentity(userId: agent.userId, tenantId: agent.tenantId, email: agent.email)))
        return agent
    }

    /// Restores a session at launch using the stored refresh token.
    /// Returns false when the user must sign in.
    public func restore() async -> Bool {
        guard (try? secrets.read(.portalRefreshToken)) != nil,
              (try? secrets.read(.agentToken)) != nil else { return false }
        return await refreshPortal()
    }

    public func signOut() async {
        if let refresh = try? secrets.read(.portalRefreshToken) {
            var logout = Endpoint<EmptyResponse>(.post, "/auth/logout", auth: .none, idempotent: false)
            logout.extraHeaders["Cookie"] = "\(Self.refreshCookieName)=\(refresh)"
            _ = try? await http.sendRaw(logout)
        }
        clearCredentials()
        emit(.signedOut)
    }

    public var lastEmail: String? { try? secrets.read(.lastEmail) }

    /// The agent token, for handing to the local Rust agent over IPC.
    public func agentTokenForDaemon() -> String? { try? secrets.read(.agentToken) }

    // MARK: - CredentialProvider

    public func bearerToken(for requirement: AuthRequirement) async -> String? {
        switch requirement {
        case .none:
            return nil
        case .agent:
            return try? secrets.read(.agentToken)
        case .portal:
            // Proactively refresh 60 s before expiry to avoid a 401 round-trip.
            if let expiry = portalAccessExpiry, expiry.timeIntervalSinceNow < 60 {
                _ = await refreshPortal()
            }
            return portalAccessToken
        }
    }

    public func refreshAfterUnauthorized(for requirement: AuthRequirement, failedToken: String) async -> Bool {
        switch requirement {
        case .none:
            return false
        case .portal:
            // Another request may already have rotated the token.
            if let current = portalAccessToken, current != failedToken { return true }
            return await refreshPortal()
        case .agent:
            if let current = try? secrets.read(.agentToken), current != failedToken { return true }
            return await refreshAgent()
        }
    }

    // MARK: - Refresh (single-flight)

    private func refreshPortal() async -> Bool {
        if let refreshTask { return await refreshTask.value }
        let task = Task<Bool, Never> { await self.performPortalRefresh() }
        refreshTask = task
        let ok = await task.value
        refreshTask = nil
        return ok
    }

    private func performPortalRefresh() async -> Bool {
        guard let refresh = try? secrets.read(.portalRefreshToken) else { return false }
        var endpoint = Endpoint<TokenResponse>(.post, "/auth/refresh", auth: .none, idempotent: false)
        endpoint.extraHeaders["Cookie"] = "\(Self.refreshCookieName)=\(refresh)"
        do {
            let (data, response) = try await http.sendRaw(endpoint)
            let token = try decode(TokenResponse.self, data, path: "/auth/refresh")
            // Rotation: the old refresh token is now revoked server-side.
            if let rotated = Self.extractRefreshCookie(from: response) {
                try secrets.write(rotated, for: .portalRefreshToken)
            }
            setPortalAccess(token)
            return true
        } catch AppError.offline {
            // Keep credentials; the UI shows offline state and retries later.
            return false
        } catch AppError.passwordChangeRequired {
            emit(.passwordChangeRequired)
            return false
        } catch {
            Log.auth.notice("portal refresh rejected; clearing session")
            clearCredentials()
            emit(.expired)
            return false
        }
    }

    private func refreshAgent() async -> Bool {
        if let agentRefreshTask { return await agentRefreshTask.value }
        let task = Task<Bool, Never> { await self.performAgentRefresh() }
        agentRefreshTask = task
        let ok = await task.value
        agentRefreshTask = nil
        return ok
    }

    private func performAgentRefresh() async -> Bool {
        guard let current = try? secrets.read(.agentToken) else { return false }
        var endpoint = Endpoint<AgentTokenResponse>(.post, "/auth/agent/refresh", auth: .none, idempotent: false)
        endpoint.extraHeaders["Authorization"] = "Bearer \(current)"
        do {
            let response = try await http.send(endpoint)
            try secrets.write(response.token, for: .agentToken)
            return true
        } catch AppError.offline {
            return false
        } catch {
            Log.auth.notice("agent token refresh rejected; clearing session")
            clearCredentials()
            emit(.expired)
            return false
        }
    }

    // MARK: - Helpers

    private func setPortalAccess(_ token: TokenResponse) {
        portalAccessToken = token.accessToken
        portalAccessExpiry = Date().addingTimeInterval(TimeInterval(max(token.expiresIn, 60)))
    }

    private func clearCredentials() {
        portalAccessToken = nil
        portalAccessExpiry = nil
        try? secrets.delete(.portalRefreshToken)
        try? secrets.delete(.agentToken)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data, path: String) throws -> T {
        do { return try JSONCoding.makeDecoder().decode(type, from: data) } catch { throw AppError.decoding(path) }
    }

    /// Extracts `wp_refresh_token` from `Set-Cookie` without using a cookie jar.
    static func extractRefreshCookie(from response: HTTPURLResponse) -> String? {
        guard let url = response.url else { return nil }
        var fields: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let key = key as? String, let value = value as? String { fields[key] = value }
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
        return cookies.first { $0.name == refreshCookieName && !$0.value.isEmpty }?.value
    }
}
