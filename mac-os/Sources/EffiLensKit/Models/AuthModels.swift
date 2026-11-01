import Foundation

// Mirrors core-services/app/schemas/auth.py — field names are load-bearing.

/// `POST /auth/login` and `POST /auth/agent/login` request (`LocalLoginRequest` / `AgentLoginRequest`).
public struct LoginRequest: Encodable, Sendable {
    public let email: String
    public let password: String
    public init(email: String, password: String) {
        self.email = email
        self.password = password
    }
}

/// `TokenResponse` — portal login/refresh. The refresh token arrives as the
/// HttpOnly cookie `wp_refresh_token`, not in the body.
public struct TokenResponse: Decodable, Sendable {
    public let accessToken: String
    public let tokenType: String
    public let expiresIn: Int
}

/// `AgentLoginResponse`.
public struct AgentLoginResponse: Decodable, Sendable {
    public let accessToken: String
    public let userId: UUID
    public let tenantId: UUID
    public let email: String
    public let expiresIn: Int
    public let refreshTokenExpiresIn: Int
    public let passwordChanged: Bool?
}

/// `AgentTokenResponse` — returned by `POST /auth/agent/refresh`
/// (note: field is `token`, not `access_token`).
public struct AgentTokenResponse: Decodable, Sendable {
    public let token: String
    public let deviceId: UUID
    public let expiresAt: Date
    public let refreshTokenExpiresIn: Int
}

/// `ChangePasswordRequest`.
public struct ChangePasswordRequest: Encodable, Sendable {
    public let currentPassword: String
    public let newPassword: String
    public init(currentPassword: String, newPassword: String) {
        self.currentPassword = currentPassword
        self.newPassword = newPassword
    }
}

/// `ForgotPasswordRequest` / `ForgotPasswordResponse`.
public struct ForgotPasswordRequest: Encodable, Sendable {
    public let email: String
    public init(email: String) { self.email = email }
}

public struct MessageResponse: Decodable, Sendable {
    public let message: String
}
