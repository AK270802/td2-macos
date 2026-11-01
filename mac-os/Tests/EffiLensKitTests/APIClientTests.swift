import XCTest
@testable import EffiLensKit

/// Scripted transport: returns queued responses in order and records requests.
final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
    struct Reply { let status: Int; let body: String; let headers: [String: String] }
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []
    private let lock = NSLock()

    init(_ replies: [Reply]) { self.replies = replies }

    func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try lock.withLock {
            requests.append(request)
            guard !replies.isEmpty else { throw URLError(.badServerResponse) }
            let reply = replies.removeFirst()
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
            return (Data(reply.body.utf8), response)
        }
    }
}

actor StubCredentials: CredentialProvider {
    var token = "old"
    var refreshCount = 0
    func bearerToken(for requirement: AuthRequirement) async -> String? { requirement == .none ? nil : token }
    func refreshAfterUnauthorized(for requirement: AuthRequirement, failedToken: String) async -> Bool {
        refreshCount += 1
        token = "new"
        return true
    }
}

final class APIClientTests: XCTestCase {
    private let config = AppConfiguration(apiOrigin: URL(string: "https://api.example.com")!, portalOrigin: nil, appVersion: "0.1.0", bundleIdentifier: "test")

    func testRefreshesOnceOn401ThenSucceeds() async throws {
        let transport = ScriptedTransport([
            .init(status: 401, body: "{\"detail\":\"expired\"}", headers: [:]),
            .init(status: 200, body: "{\"count\":3}", headers: [:]),
        ])
        let credentials = StubCredentials()
        let client = APIClient(configuration: config, transport: transport, credentials: credentials, retry: .none)
        let result = try await client.send(Endpoint<UnreadCountResponse>(.get, "/notifications/unread-count"))
        XCTAssertEqual(result.count, 3)
        let refreshCount = await credentials.refreshCount
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(transport.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer new")
        XCTAssertEqual(transport.requests.first?.url?.path, "/api/v1/notifications/unread-count")
    }

    func testPasswordChangeHeaderMapsToDedicatedError() async {
        let transport = ScriptedTransport([
            .init(status: 403, body: "{\"detail\":\"Password change required.\"}", headers: ["X-Password-Change-Required": "true"]),
        ])
        let client = APIClient(configuration: config, transport: transport, credentials: StubCredentials(), retry: .none)
        do {
            _ = try await client.send(Endpoint<UserOut>(.get, "/users/me"))
            XCTFail("expected error")
        } catch let error as AppError {
            XCTAssertEqual(error, .passwordChangeRequired)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testValidationDetailListIsJoined() {
        let data = Data("{\"detail\":[{\"loc\":[\"body\",\"end_date\"],\"msg\":\"end before start\"}]}".utf8)
        let response = HTTPURLResponse(url: URL(string: "https://x")!, statusCode: 422, httpVersion: nil, headerFields: nil)!
        XCTAssertEqual(APIClient.mapError(status: 422, data: data, response: response), .validation("end before start"))
    }

    func testOriginValidation() {
        XCTAssertNotNil(AppConfiguration.validatedOrigin("https://api.example.com/api/v1/"))
        XCTAssertEqual(AppConfiguration.validatedOrigin("https://api.example.com/api/v1")?.absoluteString, "https://api.example.com")
        XCTAssertNil(AppConfiguration.validatedOrigin("http://api.example.com"), "plain HTTP only allowed for loopback")
        XCTAssertNotNil(AppConfiguration.validatedOrigin("http://localhost:8000"))
    }

    func testRefreshCookieExtraction() {
        let response = HTTPURLResponse(
            url: URL(string: "https://api.example.com/api/v1/auth/login")!,
            statusCode: 200, httpVersion: nil,
            headerFields: ["Set-Cookie": "wp_refresh_token=abc123; HttpOnly; Path=/; SameSite=lax; Secure; Max-Age=604800"]
        )!
        XCTAssertEqual(SessionManager.extractRefreshCookie(from: response), "abc123")
    }
}
