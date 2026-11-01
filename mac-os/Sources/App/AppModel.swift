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
    /// Route requested from outside the main window (menu bar, commands).
    var requestedRoute: Route?
    private var notificationsPrimed = false
    private var unreadPollTask: Task<Void, Never>?
    private let reminder = InactiveReminder()
    /// go-agent parity: the idle warning brings the window forward with a
    /// 60 s countdown (IdleWarningSheet); set when the agent flags idle.
    private(set) var idleWarningStartedAt: Date?
    /// Opens the main window when it was closed (set by an always-alive view).
    var openMainWindowAction: (() -> Void)?
    private var wakeObserver: NSObjectProtocol?
    private var idleWarned = false

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
        observeWake()
        if !Prefs.bool(Prefs.rememberMac) {
            // "Remember this Mac" was off: forget the previous session.
            await environment.session.signOut()
            phase = .signedOut
            return
        }
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
        unreadPollTask?.cancel()
        if let agent = environment.agent {
            // Stop tracking before dropping credentials (parity with the Tauri tray Quit).
            try? await agent.stopTracking()
            try? await agent.clearSession()
        }
        await environment.session.signOut()
        user = nil
        agentLink = .unknown
        syncStatus = nil
        permissions = nil
        unreadNotifications = 0
        notificationsPrimed = false
        DesktopNotifier.updateDockBadge(0)
        phase = .signedOut
    }

    func refreshUnreadCount() async {
        guard let environment, phase == .ready else { return }
        guard let count = try? await environment.notifications.unreadCount() else { return }
        let previous = unreadNotifications
        unreadNotifications = count
        DesktopNotifier.updateDockBadge(count)
        if count > previous, previous >= 0, notificationsPrimed {
            await DesktopNotifier.postUnreadSummary(newCount: count - previous)
        }
        notificationsPrimed = true
    }

    // MARK: - Agent commands (errors are surfaced, never swallowed)

    /// Last failed agent command, shown as an alert by the shell.
    var agentCommandError: AppError?

    /// Runs one IPC command against the daemon and surfaces failures.
    func runAgent(_ operation: @escaping @Sendable (AgentClient) async throws -> Void) async {
        guard let agent = environment?.agent else {
            agentCommandError = .agentUnavailable("The tracking agent is not installed in this build.")
            return
        }
        if agentLink == .legacyConflict {
            agentCommandError = .agentUnavailable("Quit the older WorkPulse app first — running both would record time twice.")
            return
        }
        do {
            try await operation(agent)
        } catch {
            agentCommandError = (error as? AppError) ?? .agentUnavailable("The tracking agent did not respond.")
        }
    }

    // MARK: - go-agent parity: window restore, idle response, wake, breaks

    /// Brings the main window to the front (or reopens it). `float` keeps it
    /// above other windows briefly, like go-agent's idle warning.
    func restoreMainWindow(float: Bool = false) {
        NSApp.activate(ignoringOtherApps: true)
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(SceneID.main) == true }) else {
            openMainWindowAction?()
            return
        }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        window.level = .floating
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(float ? 60_000 : 400))
            window.level = .normal
        }
    }

    /// User answered the idle warning (or the countdown expired).
    /// keepWorking → idle span recorded as idle, timer keeps running;
    /// otherwise the session stops back-dated to idle start (agent rules).
    func respondToIdle(keepWorking: Bool, timedOut: Bool = false) async {
        idleWarningStartedAt = nil
        NSApp.windows.forEach { if $0.level == .floating, $0.identifier?.rawValue.hasPrefix(SceneID.main) == true { $0.level = .normal } }
        await runAgent { try await $0.resolveIdle(keepWorking: keepWorking) }
        if timedOut {
            await DesktopNotifier.post(title: "Tracking Stopped",
                                       body: "No activity detected — tracking has been stopped. Remember to start tracking when you're back at work.")
        }
    }

    /// go-agent tray "Pause": a 15-minute coffee break.
    func startCoffeeBreak() async {
        await runAgent { try await $0.startBreak(AgentBreakPayload(breakType: "Coffee Break", durationSecs: 15 * 60)) }
    }

    /// Re-sends the session before start/resume (go-agent restores the session
    /// on demand so a long-idle Mac never starts tracking unauthenticated).
    func ensureAgentSession() async {
        guard let agent = environment?.agent, isAgentConnected else { return }
        _ = await handOffSession(to: agent)
    }

    /// go-agent OnSystemWake: restore the window, then after the network has
    /// had time to reconnect refresh the session, re-hand it to the agent and
    /// sync. (The agent itself pauses tracking at sleep — `pause_for_sleep`.)
    private func observeWake() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.phase == .ready, let environment = self.environment else { return }
                self.restoreMainWindow()
                try? await Task.sleep(for: .seconds(10))
                _ = await environment.session.restore()
                await self.ensureAgentSession()
                await self.runAgentSilently { try await $0.syncNow() }
            }
        }
    }

    /// Like `runAgent` but never raises an alert (background maintenance).
    func runAgentSilently(_ operation: @escaping @Sendable (AgentClient) async throws -> Void) async {
        guard let agent = environment?.agent, agentLink != .legacyConflict else { return }
        try? await operation(agent)
    }

    /// Recovery action: re-registers the LaunchAgent (launchd starts it) and
    /// forces a fresh session hand-off on the next successful poll.
    func restartAgentConnection() {
        agentRegistration = AgentLifecycle.ensureRegistered()
        startAgentMonitoring()
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
                    self.unreadPollTask?.cancel()
                    // The daemon keeps its queue: an expired portal session is not a
                    // logout, and clearing here would discard unsynced activity.
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
        unreadPollTask?.cancel()
        unreadPollTask = Task { [weak self] in
            // API_INTEGRATION.md: notifications refresh every 60 s.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await self?.refreshUnreadCount()
            }
        }
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
                if let state {
                    if await self.reminder.update(isTracking: state.state == .running || state.state == .onBreak) {
                        // go-agent ShowMainWindowCallback: reminder also restores the window.
                        self.restoreMainWindow()
                    }
                    if state.idleWarning, !self.idleWarned {
                        // go-agent OnIdleWarning: restore + float the window, start the countdown.
                        self.idleWarningStartedAt = Date()
                        self.restoreMainWindow(float: true)
                        if !NSApp.isActive { await DesktopNotifier.postIdleWarning() }
                    }
                    if !state.idleWarning, self.idleWarned { self.idleWarningStartedAt = nil }
                    self.idleWarned = state.idleWarning
                }
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
