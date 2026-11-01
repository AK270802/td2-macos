import Foundation
import ServiceManagement
import EffiLensKit

/// Registers and supervises the bundled Rust agent (`effilens-agentd`) via
/// `SMAppService` (LaunchAgent at Contents/Library/LaunchAgents). launchd
/// restarts it on crash (`KeepAlive.SuccessfulExit = false`).
@MainActor
enum AgentLifecycle {
    static let plistName = "com.baseel.effilens.mac.agent.plist"

    enum Registration: Equatable {
        case enabled
        /// User must allow it in System Settings › General › Login Items.
        case requiresApproval
        /// The agent binary is not embedded in this build.
        case notBundled
        case failed(String)
    }

    private static var service: SMAppService { SMAppService.agent(plistName: plistName) }

    static var isBundled: Bool {
        guard let url = Bundle.main.executableURL?.deletingLastPathComponent().appending(path: "effilens-agentd") else {
            return false
        }
        return FileManager.default.isExecutableFile(atPath: url.path)
    }

    /// Idempotent: registers when needed and reports the resulting state.
    static func ensureRegistered() -> Registration {
        guard isBundled else { return .notBundled }
        switch service.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered, .notFound:
            do {
                try service.register()
                Log.agent.info("agent registered with launchd")
                return service.status == .requiresApproval ? .requiresApproval : .enabled
            } catch {
                Log.agent.error("agent registration failed: \(String(describing: error), privacy: .public)")
                return service.status == .requiresApproval ? .requiresApproval : .failed(error.localizedDescription)
            }
        @unknown default:
            return .failed("Unknown agent status")
        }
    }

    /// Stops the agent from launching (used only if the user opts out entirely).
    static func unregister() async {
        do { try await service.unregister() } catch {
            Log.agent.error("agent unregister failed: \(String(describing: error), privacy: .public)")
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
