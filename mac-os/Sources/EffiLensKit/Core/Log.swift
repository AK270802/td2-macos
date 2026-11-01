import Foundation
import os

/// Structured logging via the unified logging system (`os.Logger`).
///
/// Rules (see SECURITY_AND_PRIVACY.md):
/// - Never log tokens, passwords, cookies, window titles or screenshot data.
/// - Dynamic values default to `.private` in os_log; only mark values
///   `.public` when they are non-sensitive (HTTP status, endpoint path, counts).
public enum Log {
    public static let subsystem = "com.baseel.effilens.mac"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let network = Logger(subsystem: subsystem, category: "network")
    public static let auth = Logger(subsystem: subsystem, category: "auth")
    public static let agent = Logger(subsystem: subsystem, category: "agent")
    public static let storage = Logger(subsystem: subsystem, category: "storage")
    public static let ui = Logger(subsystem: subsystem, category: "ui")
}
