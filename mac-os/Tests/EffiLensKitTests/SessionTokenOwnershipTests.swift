import XCTest
@testable import EffiLensKit

/// In-memory SecretStore for session tests.
final class MemorySecrets: SecretStore, @unchecked Sendable {
    private var values: [SecretKey: String] = [:]
    private let lock = NSLock()
    func read(_ key: SecretKey) throws -> String? { lock.withLock { values[key] } }
    func write(_ value: String, for key: SecretKey) throws { lock.withLock { values[key] = value } }
    func delete(_ key: SecretKey) throws { lock.withLock { values[key] = nil } }
}

final class SessionTokenOwnershipTests: XCTestCase {
    private let config = AppConfiguration(apiOrigin: URL(string: "https://api.example.com")!, portalOrigin: nil, appVersion: "0.1.0", bundleIdentifier: "test")

    /// A 401 from sign-in is rejected credentials, never "session expired".
    func testLogin401IsInvalidCredentialsNotExpiredSession() async {
        let transport = ScriptedTransport([
            .init(status: 401, body: "{\"detail\":\"Invalid email or password.\"}", headers: [:]),
        ])
        let session = SessionManager(configuration: config, secrets: MemorySecrets(), transport: transport)
        do {
            try await session.signIn(email: "user@example.com", password: "wrong")
            XCTFail("expected error")
        } catch let error as AppError {
            XCTAssertNotEqual(error, .unauthenticated)
            XCTAssertEqual(error, .validation("Invalid email or password."))
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    /// With a daemon attached, an agent 401 adopts the daemon's rotated
    /// token and never calls /auth/agent/refresh (which would revoke it).
    func testAgent401AdoptsDaemonTokenWithoutRefreshing() async {
        let secrets = MemorySecrets()
        try? secrets.write("app-old", for: .agentToken)
        try? secrets.write("refresh", for: .portalRefreshToken)
        let transport = ScriptedTransport([])   // any HTTP call would fail the test
        let session = SessionManager(configuration: config, secrets: secrets, transport: transport)
        await session.setAgentTokenSource { "daemon-new" }

        let ok = await session.refreshAfterUnauthorized(for: .agent, failedToken: "app-old")
        XCTAssertTrue(ok)
        XCTAssertEqual(try secrets.read(.agentToken), "daemon-new")
        XCTAssertTrue(transport.requests.isEmpty)
    }

    /// Daemon holds the same (rejected) token: fail the request but keep the
    /// signed-in session — no credential wipe.
    func testAgent401WithSameDaemonTokenKeepsSession() async {
        let secrets = MemorySecrets()
        try? secrets.write("tok", for: .agentToken)
        try? secrets.write("refresh", for: .portalRefreshToken)
        let transport = ScriptedTransport([])
        let session = SessionManager(configuration: config, secrets: secrets, transport: transport)
        await session.setAgentTokenSource { "tok" }

        let ok = await session.refreshAfterUnauthorized(for: .agent, failedToken: "tok")
        XCTAssertFalse(ok)
        XCTAssertEqual(try secrets.read(.portalRefreshToken), "refresh")
        XCTAssertTrue(transport.requests.isEmpty)
    }
}
