import Foundation
import ServiceManagement
import EffiLensKit

/// Starts and supervises the bundled Rust agent (`effilens-agentd`) as a
/// CHILD PROCESS of EffiLens.app.
///
/// Why not a launchd LaunchAgent (SMAppService.agent): launchd makes the
/// agent its own *responsible process*, so macOS privacy (TCC) checks the
/// agent's code identity instead of EffiLens's. Users then had to grant
/// Accessibility / Screen Recording / Input Monitoring a second time to a
/// bare, ad-hoc-signed binary — which often never even appears in the
/// lists — and tracking stayed "limited" although EffiLens was allowed.
/// A child spawned by the app is attributed to the app, so one grant to
/// "EffiLens" covers capture. (Same model as the Tauri app, which spawns
/// agentd on demand.) "Open at Login" launches the app itself
/// (`LoginItem`), which then starts the agent.
@MainActor
enum AgentLifecycle {
    static let legacyPlistName = "com.baseel.effilens.mac.agent.plist"

    enum Registration: Equatable {
        case enabled
        /// Kept for UI compatibility; no longer produced (no launchd job).
        case requiresApproval
        /// The agent binary is not embedded in this build.
        case notBundled
        case failed(String)
    }

    private static var process: Process?
    private static var stopping = false
    private static var restartTask: Task<Void, Never>?
    private static var didCleanUpLegacy = false

    private static var agentURL: URL? {
        Bundle.main.executableURL?.deletingLastPathComponent().appending(path: "effilens-agentd")
    }

    static var isBundled: Bool {
        guard let url = agentURL else { return false }
        return FileManager.default.isExecutableFile(atPath: url.path)
    }

    static var isRunning: Bool { process?.isRunning == true }

    /// Idempotent: starts the agent when it is not running.
    static func ensureRegistered() -> Registration {
        guard isBundled, let url = agentURL else { return .notBundled }
        if isRunning { return .enabled }
        stopping = false
        if !didCleanUpLegacy {
            didCleanUpLegacy = true
            retireLegacyLaunchAgent()
        }
        do {
            try spawn(url)
            return .enabled
        } catch {
            Log.agent.error("agent start failed: \(String(describing: error), privacy: .public)")
            return .failed(error.localizedDescription)
        }
    }

    /// Stops the agent (app quit / sign-out of the device). SIGTERM lets it
    /// flush its state; tracking was already stopped by the caller.
    static func stop() {
        stopping = true
        restartTask?.cancel()
        if let process, process.isRunning { process.terminate() }
        process = nil
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: - Internals

    private static func spawn(_ url: URL) throws {
        let child = Process()
        child.executableURL = url
        child.arguments = ["run"]
        var env = ProcessInfo.processInfo.environment
        if let api = bundledAPIURL() { env["WORKPULSE_API_URL"] = api }
        child.environment = env
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        child.terminationHandler = { finished in
            let pid = finished.processIdentifier
            let status = finished.terminationStatus
            Task { @MainActor in handleExit(pid: pid, status: status) }
        }
        try child.run()
        process = child
        Log.agent.info("agent started (pid \(child.processIdentifier, privacy: .public))")
    }

    /// launchd-parity restart (KeepAlive, ThrottleInterval 10 s).
    private static func handleExit(pid: Int32, status: Int32) {
        guard let running = process, running.processIdentifier == pid else { return }
        process = nil
        guard !stopping else { return }
        Log.agent.error("agent exited (status \(status, privacy: .public)); restarting in 10 s")
        restartTask?.cancel()
        restartTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, !stopping else { return }
            _ = ensureRegistered()
        }
    }

    /// API URL baked into the bundled plist by embed-agent.sh.
    private static func bundledAPIURL() -> String? {
        let plist = Bundle.main.bundleURL.appending(path: "Contents/Library/LaunchAgents/\(legacyPlistName)")
        guard let dict = NSDictionary(contentsOf: plist) as? [String: Any],
              let env = dict["EnvironmentVariables"] as? [String: String],
              let url = env["WORKPULSE_API_URL"], !url.isEmpty else { return nil }
        return url
    }

    /// Earlier builds registered the agent with launchd. Unregister it and
    /// end any leftover copy (it would hold the IPC socket and run under its
    /// own TCC identity) before starting ours.
    private static func retireLegacyLaunchAgent() {
        let service = SMAppService.agent(plistName: legacyPlistName)
        if service.status == .enabled || service.status == .requiresApproval {
            do {
                try service.unregister()
                Log.agent.info("retired legacy launchd agent")
            } catch {
                Log.agent.error("legacy agent unregister failed: \(String(describing: error), privacy: .public)")
            }
        }
        let kill = Process()
        kill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        kill.arguments = ["-x", "effilens-agentd"]
        kill.standardOutput = FileHandle.nullDevice
        kill.standardError = FileHandle.nullDevice
        try? kill.run()
        kill.waitUntilExit()
    }
}
