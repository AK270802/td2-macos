import Foundation
import Security

/// Minimal generic-password Keychain wrapper.
///
/// Items are `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (never synced
/// to iCloud, never migrated to another Mac) and scoped to a service name
/// derived from the bundle identifier, so they are isolated from the legacy
/// Tauri app (`com.baseel.workpulse`).
public protocol SecretStore: Sendable {
    func read(_ key: SecretKey) throws -> String?
    func write(_ value: String, for key: SecretKey) throws
    func delete(_ key: SecretKey) throws
}

public enum SecretKey: String, CaseIterable, Sendable {
    /// Rotating portal refresh token (`wp_refresh_token` cookie value).
    case portalRefreshToken = "portal.refresh"
    /// Opaque agent device token (`/auth/agent/login`).
    case agentToken = "agent.token"
    /// Last signed-in email (not secret, but kept with the account for convenience).
    case lastEmail = "account.email"
}

public struct KeychainStore: SecretStore {
    public let service: String

    public init(service: String) {
        self.service = service
    }

    private func baseQuery(_ key: SecretKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            // Data-protection keychain requires a provisioned keychain-access-group,
            // which unsigned dev builds lack (errSecMissingEntitlement). Release
            // builds may opt in once Developer ID signing is configured.
        ]
    }

    public func read(_ key: SecretKey) throws -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    public func write(_ value: String, for key: SecretKey) throws {
        let data = Data(value.utf8)
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(baseQuery(key) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery(key)
            add.merge(update) { _, new in new }
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    public func delete(_ key: SecretKey) throws {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

public struct KeychainError: Error, Sendable, CustomStringConvertible {
    public let status: OSStatus
    public var description: String {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
        return "Keychain error \(status): \(message)"
    }
}

/// In-memory store for tests and previews.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private var values: [SecretKey: String] = [:]
    private let lock = NSLock()
    public init() {}
    public func read(_ key: SecretKey) throws -> String? { lock.withLock { values[key] } }
    public func write(_ value: String, for key: SecretKey) throws { lock.withLock { values[key] = value } }
    public func delete(_ key: SecretKey) throws { lock.withLock { values[key] = nil } }
}
