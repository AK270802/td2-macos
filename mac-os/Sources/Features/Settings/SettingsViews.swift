import AppKit
import SwiftUI
import UserNotifications
import EffiLensKit

/// Settings window (⌘,) and the sidebar's Settings / About routes.
/// Organisation-controlled values (screenshot interval, idle threshold, blur,
/// retention) come from `GET /agent/config` and are read-only here — the
/// native app never overrides server policy.
struct SettingsRootView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case general = "General", tracking = "Tracking", screenshots = "Screenshots", notifications = "Notifications"
        case appearance = "Appearance", account = "Account", about = "About", diagnostics = "Diagnostics"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .tracking: return "timer"
            case .screenshots: return "camera.viewfinder"
            case .notifications: return "bell.badge"
            case .appearance: return "paintpalette"
            case .account: return "person.crop.circle"
            case .about: return "info.circle"
            case .diagnostics: return "stethoscope"
            }
        }
    }

    @Environment(AppModel.self) private var model
    @State var pane: Pane = .general

    var body: some View {
        TabView(selection: $pane) {
            ForEach(Pane.allCases) { p in
                content(p)
                    .tabItem { Label(p.rawValue, systemImage: p.symbol) }
                    .tag(p)
            }
        }
        .frame(minWidth: 620, minHeight: 460)
    }

    @ViewBuilder
    private func content(_ pane: Pane) -> some View {
        if let environment = model.environment {
            switch pane {
            case .general: GeneralSettingsPane()
            case .tracking: TrackingSettingsPane(environment: environment, focus: .tracking)
            case .screenshots: TrackingSettingsPane(environment: environment, focus: .screenshots)
            case .notifications: NotificationSettingsPane()
            case .appearance: AppearanceSettingsPane()
            case .account: AccountSettingsPane(environment: environment)
            case .about: AboutPane()
            case .diagnostics: DiagnosticsPane()
            }
        } else {
            ContentUnavailableView("Unavailable", systemImage: "exclamationmark.triangle", description: Text("EffiLens could not load its configuration."))
        }
    }
}

// MARK: - General

struct GeneralSettingsPane: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Prefs.menuBarTimer) private var menuBarTimer = true
    @AppStorage(Prefs.confirmQuitWhileTracking) private var confirmQuit = true

    // Same two settings as the go-agent Settings modal, edited as a draft and
    // applied with Save Settings (Cancel discards).
    @State private var draftInterval = Prefs.reminderIntervalMin
    @State private var draftLaunchAtLogin = LoginItem.isEnabled
    @State private var saveError: String?
    @State private var saved = false

    var body: some View {
        Form {
            Section("Settings") {
                Picker("Reminder Notification Interval (When Inactive)", selection: $draftInterval) {
                    Text("Never / Disable").tag(0)
                    Text("Every 5 minutes").tag(5)
                    Text("Every 10 minutes").tag(10)
                    Text("Every 15 minutes").tag(15)
                    Text("Every 30 minutes").tag(30)
                    Text("Every 60 minutes").tag(60)
                }
                Toggle("Launch at Mac Startup", isOn: $draftLaunchAtLogin)
                if let saveError { Text(saveError).font(Typo.caption).foregroundStyle(Palette.danger) }
                HStack {
                    if saved { Label("Saved", systemImage: "checkmark.circle").foregroundStyle(Palette.success).font(Typo.caption) }
                    Spacer()
                    Button("Cancel") { reset() }
                    Button("Save Settings") { save() }.buttonStyle(.borderedProminent)
                }
            }
            Section("Background agent") {
                LabeledContent("Status", value: registrationText)
                HStack {
                    Button("Open Login Items…") { AgentLifecycle.openLoginItemsSettings() }
                    Button("Reconnect Agent") { model.restartAgentConnection() }
                }
            }
            Section("Behaviour") {
                Toggle("Show timer in the menu bar", isOn: $menuBarTimer)
                Toggle("Confirm before quitting while tracking", isOn: $confirmQuit)
                Button("Show Mini Timer") { openWindow(id: SceneID.miniTimer) }
            }
            Section("Server") {
                LabeledContent("API", value: model.environment?.configuration.apiOrigin.absoluteString ?? "—")
                LabeledContent("Web portal", value: model.environment?.configuration.portalOrigin?.absoluteString ?? "—")
            }
        }
        .formStyle(.grouped)
        .onAppear { reset() }
    }

    private func reset() {
        draftInterval = Prefs.reminderIntervalMin
        draftLaunchAtLogin = LoginItem.isEnabled
        saveError = nil
        saved = false
    }

    private func save() {
        UserDefaults.standard.set(draftInterval, forKey: Prefs.reminderInterval)
        saveError = LoginItem.set(enabled: draftLaunchAtLogin)
        draftLaunchAtLogin = LoginItem.isEnabled
        saved = saveError == nil
    }

    private var registrationText: String {
        switch model.agentRegistration {
        case .enabled: return model.isAgentConnected ? "Running" : "Registered — waiting for agent"
        case .requiresApproval: return "Needs approval in Login Items"
        case .notBundled: return "Not included in this build"
        case .failed(let message): return "Registration failed: \(message)"
        case .none: return "Not started (sign in first)"
        }
    }
}

// MARK: - Tracking & screenshots (read-only organisation policy)

struct TrackingSettingsPane: View {
    enum Focus { case tracking, screenshots }
    let environment: AppEnvironment
    let focus: Focus
    @Environment(AppModel.self) private var model
    @State private var config: Loadable<AgentConfigResponse> = .idle

    var body: some View {
        Form {
            LoadStateView(state: config, retry: { Task { await load() } }) { c in
                switch focus {
                case .tracking:
                    Section("Set by your organisation") {
                        LabeledContent("Idle after", value: Format.duration(c.idleThresholdSec))
                        LabeledContent("Activity sampled every", value: "\(c.captureIntervalSec) s")
                        LabeledContent("Sync interval", value: "\(c.batchSyncIntervalMin) min")
                        LabeledContent("Breaks", value: c.breaksArePaid ? "Paid" : "Unpaid")
                        LabeledContent("Local data kept", value: "\(c.retentionDays) days")
                    }
                    Section("Privacy") {
                        Label("Keystrokes are counted, never recorded.", systemImage: "keyboard")
                        Label("Websites are stored as domains only (e.g. example.com).", systemImage: "globe")
                        Label("Nothing is captured unless you are tracking a task.", systemImage: "pause.circle")
                    }
                case .screenshots:
                    Section("Set by your organisation") {
                        LabeledContent("Screenshots", value: c.screenshotsEnabled ? "Enabled" : "Disabled")
                        if c.screenshotsEnabled {
                            LabeledContent("Interval", value: Format.duration(c.screenshotIntervalSec))
                            LabeledContent("Blur radius", value: "\(c.blurRadius)")
                        }
                    }
                    Section("How screenshots work") {
                        Label("Only the active window is captured — never the whole screen.", systemImage: "macwindow")
                        Label("Images are blurred before they are saved or uploaded.", systemImage: "drop")
                        Label(screenPermissionText, systemImage: "rectangle.dashed.badge.record")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task { await load() }
    }

    private var screenPermissionText: String {
        guard let p = model.permissions else { return "Screen Recording status unknown (agent offline)." }
        return p.screenRecording ? "Screen Recording is allowed." : "Screen Recording is not allowed — screenshots are skipped."
    }

    private func load() async {
        config = .loading
        do { config = .loaded(try await environment.agentAPI.config()) } catch { config = .failed(DashboardViewModel.map(error)) }
    }
}

// MARK: - Notifications

struct NotificationSettingsPane: View {
    @AppStorage(Prefs.desktopNotifications) private var desktop = true
    @AppStorage(Prefs.dockBadge) private var badge = true
    @Environment(AppModel.self) private var model
    @State private var status: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            Section("macOS notifications") {
                LabeledContent("Permission", value: statusText)
                if status == .notDetermined {
                    Button("Allow Notifications…") { Task { await DesktopNotifier.requestAuthorization(); await refresh() } }
                } else if status == .denied {
                    Button("Open Notification Settings…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
                    }
                }
                Toggle("Notify me about new EffiLens notifications", isOn: $desktop)
                Toggle("Show unread count on the Dock icon", isOn: $badge)
                    .onChange(of: badge) { _, _ in DesktopNotifier.updateDockBadge(model.unreadNotifications) }
            }
            Section {
                Text("Leave approvals, rejections and other alerts come from your organisation's server. Email and portal notification preferences are managed in the web portal.")
                    .font(Typo.caption).foregroundStyle(Palette.textSecondary)
            }
        }
        .formStyle(.grouped)
        .task { await refresh() }
    }

    private var statusText: String {
        switch status {
        case .authorized, .provisional: return "Allowed"
        case .denied: return "Denied in System Settings"
        case .notDetermined: return "Not requested yet"
        @unknown default: return "Unknown"
        }
    }

    private func refresh() async { status = await DesktopNotifier.authorizationStatus() }
}

// MARK: - Appearance

struct AppearanceSettingsPane: View {
    @AppStorage(Prefs.appearance) private var appearance = "system"

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                Text("Match System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.radioGroup)
            Text("Accent colours follow the EffiLens brand in both modes.").font(Typo.caption).foregroundStyle(Palette.textSecondary)
        }
        .formStyle(.grouped)
    }
}

extension View {
    /// Applies the user's appearance preference (nil = follow macOS).
    func effiLensAppearance(_ raw: String) -> some View {
        preferredColorScheme(raw == "light" ? .light : (raw == "dark" ? .dark : nil))
    }
}

// MARK: - Account

struct AccountSettingsPane: View {
    let environment: AppEnvironment
    @Environment(AppModel.self) private var model
    @State private var profile: UserProfileOut?
    @State private var current = ""
    @State private var new = ""
    @State private var confirm = ""
    @State private var working = false
    @State private var message: Result<String, AppError>?
    @State private var confirmSignOut = false

    var body: some View {
        Form {
            Section("Profile") {
                LabeledContent("Name", value: model.user?.displayName ?? "—")
                LabeledContent("Email", value: model.user?.email ?? "—")
                LabeledContent("Role", value: model.role.displayName)
                LabeledContent("Organisation", value: model.user?.organizationName ?? "—")
                LabeledContent("Manager", value: profile?.managerName ?? "—")
                LabeledContent("Time zone", value: model.user?.timezone ?? "—")
            }
            Section("Change password") {
                SecureField("Current password", text: $current)
                SecureField("New password", text: $new)
                SecureField("Confirm new password", text: $confirm)
                if !confirm.isEmpty, confirm != new { Text("Passwords don't match.").font(Typo.caption).foregroundStyle(Palette.danger) }
                switch message {
                case .success(let text): Label(text, systemImage: "checkmark.circle").foregroundStyle(Palette.success)
                case .failure(let error): Label(error.userMessage, systemImage: "exclamationmark.circle").foregroundStyle(Palette.danger)
                case .none: EmptyView()
                }
                Button("Change Password") { Task { await changePassword() } }
                    .disabled(working || current.isEmpty || new.count < 8 || new != confirm)
            }
            Section {
                Button("Sign Out…", role: .destructive) { confirmSignOut = true }
                Text("Signing out stops tracking and removes this account's unsynced activity from this Mac.")
                    .font(Typo.caption).foregroundStyle(Palette.textSecondary)
            }
        }
        .formStyle(.grouped)
        .task { profile = try? await environment.profile.profile() }
        .confirmationDialog("Sign out of EffiLens?", isPresented: $confirmSignOut) {
            Button("Sign Out", role: .destructive) { Task { await model.signOut() } }
        } message: {
            Text(pendingText)
        }
    }

    private var pendingText: String {
        if let pending = model.syncStatus?.pendingEvents, pending > 0 {
            return "\(pending) activity record(s) have not synced yet and will be removed from this Mac."
        }
        return "Tracking stops on this Mac."
    }

    private func changePassword() async {
        working = true
        defer { working = false }
        do {
            _ = try await environment.profile.changePassword(ChangePasswordRequest(currentPassword: current, newPassword: new))
            current = ""; new = ""; confirm = ""
            message = .success("Password changed.")
        } catch {
            message = .failure(DashboardViewModel.map(error))
        }
    }
}

// MARK: - About

struct AboutPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: Space.l) {
            Image("BrandLockup").resizable().interpolation(.high).scaledToFit().frame(height: 72).accessibilityLabel("EffiLens")
            Text("Version \(model.environment?.configuration.appVersion ?? "—")").font(Typo.body)
            Text("Development build · unsigned").font(Typo.caption).foregroundStyle(Palette.warning)
            Text("© Baseel. All rights reserved.").font(Typo.caption).foregroundStyle(Palette.textSecondary)
            if let portal = model.environment?.configuration.portalOrigin {
                Link("Open Web Portal", destination: portal)
            }
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Diagnostics (no tokens, no personal content)

struct DiagnosticsPane: View {
    @Environment(AppModel.self) private var model
    @State private var copied = false

    var body: some View {
        Form {
            Section("Agent") {
                LabeledContent("Connection", value: linkText)
                LabeledContent("Agent version", value: model.syncStatus?.agentVersion ?? "—")
                LabeledContent("Queued events", value: model.syncStatus.map { "\($0.pendingEvents)" } ?? "—")
                LabeledContent("Last sync", value: model.syncStatus?.lastSync.map { $0.formatted(date: .abbreviated, time: .standard) } ?? "—")
                LabeledContent("Last result", value: model.syncStatus?.lastResult ?? "—")
                HStack {
                    Button("Sync Now") { Task { await model.runAgent { try await $0.syncNow() } } }.disabled(!model.isAgentConnected)
                    Button("Reconnect Agent") { model.restartAgentConnection() }
                }
            }
            Section("Permissions (reported by the agent)") {
                LabeledContent("Accessibility", value: flag(model.permissions?.accessibility))
                LabeledContent("Screen Recording", value: flag(model.permissions?.screenRecording))
                LabeledContent("Input Monitoring", value: flag(model.permissions?.inputMonitoring))
            }
            Section("Paths") {
                LabeledContent("Data", value: (try? AgentPaths.supportDirectory().path) ?? "—")
                Text("Logs: Console.app → search “effilens”, or run `log stream --predicate 'subsystem BEGINSWITH \"com.baseel.effilens\"'`.")
                    .font(Typo.caption).foregroundStyle(Palette.textSecondary).textSelection(.enabled)
            }
            Section {
                Button(copied ? "Copied" : "Copy Diagnostics") { copy() }
                Text("Copied text contains versions, states and counts only — no tokens, emails or activity content.")
                    .font(Typo.caption).foregroundStyle(Palette.textSecondary)
            }
        }
        .formStyle(.grouped)
    }

    private var linkText: String {
        switch model.agentLink {
        case .connected(let s): return "Connected (\(s.state.rawValue))"
        case .legacyConflict: return "Blocked — legacy WorkPulse agent running"
        case .unavailable: return "Not reachable"
        case .unknown: return "Not started"
        }
    }

    private func flag(_ value: Bool?) -> String { value.map { $0 ? "Allowed" : "Not allowed" } ?? "Unknown" }

    private func copy() {
        let config = model.environment?.configuration
        let text = """
        EffiLens \(config?.appVersion ?? "?") (\(config?.bundleIdentifier ?? "?"))
        macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        API host: \(config?.apiOrigin.host() ?? "?")
        Agent: \(linkText); registration: \(String(describing: model.agentRegistration))
        Agent version: \(model.syncStatus?.agentVersion ?? "?"); queued: \(model.syncStatus?.pendingEvents ?? -1); last result: \(model.syncStatus?.lastResult ?? "?")
        Permissions: AX=\(flag(model.permissions?.accessibility)) SR=\(flag(model.permissions?.screenRecording)) IM=\(flag(model.permissions?.inputMonitoring))
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
    }
}

// MARK: - Mini timer (floating window)

struct MiniTimerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Space.m) {
            Circle()
                .fill(model.timerState?.state == .running ? Palette.success : (model.timerState?.state == .onBreak ? Palette.warning : Palette.textTertiary))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(Format.clock(model.timerState?.elapsedSecs ?? 0)).font(Typo.timerCompact).monospacedDigit()
                Text(model.timerState?.task?.taskName ?? (model.isAgentConnected ? "No task" : "Agent offline"))
                    .font(Typo.caption).foregroundStyle(Palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: Space.s)
            Button {
                Task { await model.runAgent { try await $0.togglePlayPause() } }
            } label: {
                Image(systemName: model.timerState?.state == .running ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.borderless)
            .disabled(model.timerState?.task == nil)
            .help(model.timerState?.state == .running ? "Pause" : "Resume")
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .frame(width: 240)
        .background(FloatingWindowConfigurator())
    }
}

/// Keeps the mini timer above other windows on every Space (macOS 14 has no
/// SwiftUI `windowLevel`, so the hosting NSWindow is configured directly).
struct FloatingWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.level = .floating
            window.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
            window.isMovableByWindowBackground = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Update dialog

@MainActor
enum UpdateDialog {
    /// No native update feed exists yet (API_INTEGRATION.md gap B7), so the
    /// dialog says so instead of pretending to check.
    static func present(version: String) {
        let alert = NSAlert()
        alert.messageText = "Software Update"
        alert.informativeText = "You're running EffiLens \(version) (development build).\n\nAutomatic updates for the native Mac app are not available yet. New versions are distributed as DMG/PKG installers from your administrator."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
