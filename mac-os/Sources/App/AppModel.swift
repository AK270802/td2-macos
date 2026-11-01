import AppKit
import Foundation
import Observation
import EffiLensKit

/// App-wide, main-actor state: authentication phase, current user, agent
/// status. Feature screens own their own view models.
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case launching
        case signedOut
        case consentRequired(ConsentStatusResponse)
        case passwordChangeRequired
        case ready
        case configurationError(String)
    }

    enum AgentLink: Equatable {
        case unknown
        case connected(AgentTimerState)
        /// The native agent isn't running/installed yet (Milestone 3).
        case unavailable
        /// A legacy Tauri agent is running — tracking is blocked to prevent duplicates.
        case legacyConflict
    }

    private(set) var phase: Phase = .launching
    private(set) var user: UserOut?
    private(set) var agentLink: AgentLink = .unknown
    private(set) var syncStatus: AgentSyncStatus?
    var unreadNotifications = 0

    let environment: AppEnvironment?
    private var sessionEventsTask: Task<Void, Never>?
    private var agentPollTask: Task<Void, Never>?

    init(environment: AppEnvironment?, configurationError: String? = nil) {
        self.environment = environment
        if let configurationError { phase = .configurationError(configurationError) }
    }

    var role: UserRole { user?.roleValue ?? .user }

    // MARK: - Lifecycle

    func start() async {
        guard let environment, phase == .launching else { return }
        observeSession(environment.session)
        if await environment.session.restore() {
            await completeSignIn()
        } else {
            phase = .signedOut
        }
    }

    /// Called after a successful credential sign-in or restore.
    func completeSignIn() async {
        guard let environment else { return }
        do {
            user = try await environment.profile.me()
            let consent = try await environment.consent.status()
            phase = consent.isAccepted ? .ready : .consentRequired(consent)
            if phase == .ready { startAgentMonitoring() }
            await refreshUnreadCount()
        } catch AppError.passwordChangeRequired {
            phase = .passwordChangeRequired
        } catch {
            Log.app.error("post-sign-in bootstrap failed")
            phase = .signedOut
        }
    }

    func consentAccepted() async {
        phase = .ready
        startAgentMonitoring()
        await refreshUnreadCount()
    }

    func signOut() async {
        guard let environment else { return }
        agentPollTask?.cancel()
        if let agent = environment.agent {
            // Stop tracking before dropping credentials (parity with the Tauri tray Quit).
            try? await agent.stopTracking()
            try? await agent.clearSession()
        }
        await environment.session.signOut()
        user = nil
        agentLink = .unknown
        phase = .signedOut
    }

    func refreshUnreadCount() async {
        guard let environment, phase == .ready else { return }
        if let count = try? await environment.notifications.unreadCount() { unreadNotifications = count }
    }

    // MARK: - Session events

    private func observeSession(_ session: SessionManager) {
        sessionEventsTask?.cancel()
        sessionEventsTask = Task { [weak self] in
            let stream = await session.events()
            for await event in stream {
                guard let self else { return }
                switch event {
                case .expired:
                    self.agentPollTask?.cancel()
                    self.user = nil
                    self.phase = .signedOut
                case .passwordChangeRequired:
                    self.phase = .passwordChangeRequired
                case .signedIn, .signedOut:
                    break
                }
            }
        }
    }

    // MARK: - Agent monitoring

    /// Polls the local agent's state at 1 Hz while visible state needs it.
    /// IPC is local and cheap; network is never polled at this rate.
    private func startAgentMonitoring() {
        guard let agent = environment?.agent else { agentLink = .unavailable; return }
        agentPollTask?.cancel()
        agentPollTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                let link: AgentLink
                if let state = try? await agent.state() {
                    link = .connected(state)
                } else if LegacyAgentDetector.isLegacyAgentPresent() {
                    link = .legacyConflict
                } else {
                    link = .unavailable
                }
                var sync: AgentSyncStatus?
                if tick % 15 == 0, case .connected = link { sync = try? await agent.syncStatus() }
                guard let self else { return }
                if self.agentLink != link { self.agentLink = link }
                if let sync { self.syncStatus = sync }
                tick += 1
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

/// Detects the legacy Tauri agent so the two never track simultaneously
/// (the backend would otherwise revoke each other's device token on login and
/// screenshots/events could be duplicated).
enum LegacyAgentDetector {
    /// Bundle identifier of the legacy Tauri app (app/src-tauri/tauri.conf.json).
    static let legacyBundleIdentifier = "com.baseel.workpulse"

    static func isLegacyAgentPresent() -> Bool {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: legacyBundleIdentifier).isEmpty {
            return true
        }
        // agentd runs headless as a sidecar; its socket ($TMPDIR/workpulse-agent.sock)
        // is the reliable signal. A stale file after a crash is removed by agentd on
        // its next start, so a false positive is short-lived and errs on the safe side.
        return FileManager.default.fileExists(atPath: AgentPaths.legacySocketURL.path)
    }
}
