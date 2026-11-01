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
    private(set) var permissions: AgentPermissions?
    private(set) var agentRegistration: AgentLifecycle.Registration?
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

    func refreshPermissions() async {
        guard let agent = environment?.agent else { return }
        if let value = try? await agent.permissions() { permissions = value }
    }

    /// Hands the agent token to the daemon. Called on every (re)connection:
    /// the daemon may have been (re)started by launchd after sign-in. The
    /// daemon treats a repeat for the same user as a no-op and wipes local
    /// data first if the account changed.
    private func handOffSession(to agent: AgentClient) async -> Bool {
        guard let environment, let user,
              let token = await environment.session.agentTokenForDaemon(),
              let tenant = await environment.session.tenantId else { return false }
        do {
            try await agent.setSession(AgentSessionPayload(
                accessToken: token,
                userId: user.id.uuidString.lowercased(),
                tenantId: tenant.uuidString.lowercased(),
                apiBaseUrl: environment.configuration.apiOrigin.absoluteString
            ))
            return true
        } catch {
            Log.agent.error("session hand-off to agent failed")
            return false
        }
    }

    /// Registers the bundled agent with launchd, then polls it at 1 Hz over
    /// the local socket (cheap; the network is never polled at this rate).
    /// Reconnects automatically when launchd restarts the agent.
    private func startAgentMonitoring() {
        agentRegistration = AgentLifecycle.ensureRegistered()
        guard let agent = environment?.agent else { agentLink = .unavailable; return }
        agentPollTask?.cancel()
        agentPollTask = Task { [weak self] in
            var tick = 0
            var sessionDelivered = false
            while !Task.isCancelled {
                let state = try? await agent.state()
                if state == nil { sessionDelivered = false }
                if state != nil, !sessionDelivered {
                    sessionDelivered = await self?.handOffSession(to: agent) ?? false
                }
                // A running legacy Tauri agent always wins the banner: the
                // native agent refuses to start tracking while it is present.
                let link: AgentLink
                if LegacyAgentDetector.isLegacyAgentPresent() {
                    link = .legacyConflict
                } else if let state {
                    link = .connected(state)
                } else {
                    link = .unavailable
                }
                var sync: AgentSyncStatus?
                var perms: AgentPermissions?
                if tick % 15 == 0, state != nil {
                    sync = try? await agent.syncStatus()
                    perms = try? await agent.permissions()
                }
                guard let self else { return }
                if self.agentLink != link { self.agentLink = link }
                if let sync { self.syncStatus = sync }
                if let perms, perms != self.permissions { self.permissions = perms }
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
