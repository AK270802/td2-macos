import Foundation

/// Static, non-secret runtime configuration.
///
/// Values come from the app bundle's Info.plist (populated per build
/// configuration by project.yml) and may be overridden by the user in
/// Settings → Account → Server (persisted in `UserDefaults`).
/// Secrets are never stored here — see `KeychainStore`.
public struct AppConfiguration: Sendable, Equatable {
    /// Backend origin without the `/api/v1` suffix, e.g. `https://api.example.com`.
    public var apiOrigin: URL
    /// Web portal origin used for "Open in portal" links. Optional because it
    /// is not yet confirmed for every environment.
    public var portalOrigin: URL?
    /// Version string sent as `X-Agent-Version` / `User-Agent`.
    public var appVersion: String
    /// Bundle identifier, used for Keychain service names and data paths.
    public var bundleIdentifier: String

    public static let apiPrefix = "/api/v1"

    public var apiBaseURL: URL {
        apiOrigin.appending(path: Self.apiPrefix)
    }

    public init(apiOrigin: URL, portalOrigin: URL?, appVersion: String, bundleIdentifier: String) {
        self.apiOrigin = apiOrigin
        self.portalOrigin = portalOrigin
        self.appVersion = appVersion
        self.bundleIdentifier = bundleIdentifier
    }

    /// UserDefaults key for a user-supplied server override.
    public static let serverOverrideKey = "effilens.serverOverride"

    /// Resolve configuration from a bundle + defaults. Fails only if neither
    /// the bundle nor an override provides a valid HTTPS (or localhost HTTP) origin.
    public static func load(bundle: Bundle = .main, defaults: UserDefaults = .standard) throws -> AppConfiguration {
        let info = bundle.infoDictionary ?? [:]
        let version = (info["CFBundleShortVersionString"] as? String) ?? "0.0.0"
        let identifier = bundle.bundleIdentifier ?? "com.baseel.effilens.mac"

        let candidate = defaults.string(forKey: serverOverrideKey)
            ?? (info["EffiLensAPIBaseURL"] as? String)
            ?? ""
        guard let api = Self.validatedOrigin(candidate) else {
            throw AppError.configuration("No valid API server is configured.")
        }
        let portal = (info["EffiLensPortalURL"] as? String).flatMap(Self.validatedOrigin)
        return AppConfiguration(apiOrigin: api, portalOrigin: portal, appVersion: version, bundleIdentifier: identifier)
    }

    /// Accepts `https://host[:port]` anywhere and `http://` only for loopback
    /// development hosts. Strips a trailing `/api/v1` if the user pasted it.
    public static func validatedOrigin(_ raw: String) -> URL? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        if trimmed.hasSuffix(apiPrefix) { trimmed.removeLast(apiPrefix.count) }
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              let host = url.host(), !host.isEmpty
        else { return nil }
        switch scheme {
        case "https":
            return url
        case "http" where ["localhost", "127.0.0.1", "::1"].contains(host):
            return url
        default:
            return nil
        }
    }
}
