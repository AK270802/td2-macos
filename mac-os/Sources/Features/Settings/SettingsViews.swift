import AppKit
import SwiftUI
import UserNotifications
import EffiLensKit

// Settings (prototype V.settings): centred icon tab bar, content max 640 pt,
// `.set-group` / `.set-row` rows. Organisation-controlled values (screenshot
// interval, idle threshold, blur, retention) come from `GET /agent/config`
// and are shown read-only — no dummy toggles.

struct SettingsRootView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case general = "General", tracking = "Tracking", screenshots = "Screenshots"
        case notifications = "Notifications", appearance = "Appearance", account = "Account"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .tracking: return "clock"
            case .screenshots: return "rectangle.dashed"
            case .notifications: return "bell"
            case .appearance: return "sun.max"
            case .account: return "person"
            }
        }
    }

    @Environment(AppModel.self) private var model
    @AppStorage("effilens.settings.pane") private var paneRaw = Pane.general.rawValue

    private var pane: Pane { Pane(rawValue: paneRaw) ?? .general }

    var body: some View {
        Page(maxWidth: 640) {
            HStack(spacing: 4) {
                ForEach(Pane.allCases) { p in
                    Button {
                        paneRaw = p.rawValue
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: p.symbol).font(.system(size: 18))
                            Text(p.rawValue).font(.system(size: 11.5))
                        }
                        .foregroundStyle(pane == p ? Palette.accentText : Palette.textSecondary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        .background(pane == p ? Palette.accent.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(pane == p ? .isSelected : [])
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 6)

            if let environment = model.environment {
                switch pane {
                case .general: GeneralSettingsPane()
                case .tracking: OrgPolicyPane(environment: environment, focus: .tracking)
                case .screenshots: OrgPolicyPane(environment: environment, focus: .screenshots)
                case .notifications: NotificationSettingsPane()
                case .appearance: AppearanceSettingsPane()
                case .account: AccountSettingsPane(environment: environment)
                }
            }
        }
        .background(Palette.canvas)
    }
}

// MARK: - General (go-agent Settings parity + app behaviour)

struct GeneralSettingsPane: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Prefs.menuBarTimer) private var menuBarTimer = true
    @AppStorage(Prefs.dockBadge) private var dockBadge = true
    @AppStorage(Prefs.confirmQuitWhileTracking) private var confirmQuit = true

    // The go-agent Settings modal: two settings edited as a draft and applied
    // with Save Settings (Cancel discards).
    @State private var draftInterval = Prefs.reminderIntervalMin
    @State private var draftLaunchAtLogin = LoginItem.isEnabled
    @State private var saveError: String?
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SetGroup {
                SetRow(title: "Reminder notification interval", detail: "When you're signed in but not tracking") {
                    Picker("", selection: $draftInterval) {
                        Text("Never / Disable").tag(0)
                        Text("Every 5 minutes").tag(5)
                        Text("Every 10 minutes").tag(10)
                        Text("Every 15 minutes").tag(15)
                        Text("Every 30 minutes").tag(30)
                        Text("Every 60 minutes").tag(60)
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
                SetToggleRow(title: "Launch at Mac startup", detail: "Open EffiLens when you log in", isOn: $draftLaunchAtLogin, isLast: true)
            }
            HStack {
                if let saveError { Text(saveError).font(Typo.caption).foregroundStyle(Palette.danger) }
                else if saved { Label("Saved", systemImage: "checkmark.circle").font(Typo.caption).foregroundStyle(Palette.success) }
                Spacer()
                Button("Cancel") { reset() }.buttonStyle(.effi)
                Button("Save Settings") { save() }.buttonStyle(.effiPrimary)
            }
            .padding(.top, -6)
            .padding(.bottom, Space.l)

            SetGroup {
                SetToggleRow(title: "Show timer in the menu bar", isOn: $menuBarTimer)
                SetToggleRow(title: "Show Dock badge for unread", isOn: $dockBadge)
                    .onChange(of: dockBadge) { _, _ in DesktopNotifier.updateDockBadge(model.unreadNotifications) }
                SetToggleRow(title: "Confirm before quitting while tracking", isOn: $confirmQuit, isLast: true)
            }
            SetGroup(title: "Tracking agent") {
                SetRow(title: "Status", detail: nil) { Pill(text: registrationText.0, kind: registrationText.1) }
                SetRow(title: "Login Items", detail: "The agent keeps tracking when the window is closed", isLast: true) {
                    HStack(spacing: 6) {
                        Button("Open…") { AgentLifecycle.openLoginItemsSettings() }.buttonStyle(.effi)
                        Button("Reconnect") { model.restartAgentConnection() }.buttonStyle(.effi)
                    }
                }
            }
            SetGroup(title: "Server") {
                SetRow("API", value: model.environment?.configuration.apiOrigin.host() ?? "—")
                SetRow("Web portal", value: model.environment?.configuration.portalOrigin?.host() ?? "—", isLast: true)
            }
        }
        .onAppear { reset() }
    }

    private var registrationText: (String, Pill.Kind) {
        switch model.agentRegistration {
        case .enabled: return model.isAgentConnected ? ("Running", .ok) : ("Waiting for agent", .wait)
        case .requiresApproval: return ("Needs approval in Login Items", .wait)
        case .notBundled: return ("Not included in this build", .no)
        case .failed: return ("Registration failed", .no)
        case .none: return ("Not started", .gray)
        }
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
}

// MARK: - Tracking & screenshots (read-only organisation policy)

struct OrgPolicyPane: View {
    enum Focus { case tracking, screenshots }
    let environment: AppEnvironment
    let focus: Focus
    @Environment(AppModel.self) private var model
    @State private var config: Loadable<AgentConfigResponse> = .idle

    var body: some View {
        LoadStateView(state: config, retry: { Task { await load() } }) { c in
            VStack(alignment: .leading, spacing: 0) {
                switch focus {
                case .tracking:
                    SetGroup(title: "Set by your organisation") {
                        SetRow("Detect idle time after", value: Format.duration(c.idleThresholdSec))
                        SetRow("Activity sampled every", value: "\(c.captureIntervalSec) s")
                        SetRow("Sync interval", value: "\(c.batchSyncIntervalMin) min")
                        SetRow("Breaks", value: c.breaksArePaid ? "Paid" : "Unpaid")
                        SetRow("Local data kept", value: "\(c.retentionDays) days", isLast: true)
                    }
                    SetGroup(title: "Shortcuts") {
                        SetRow(title: "Start / pause", detail: nil) { Pill(text: "⌃⌥Space", kind: .gray) }
                        SetRow(title: "Stop", detail: nil) { Pill(text: "⌃⌥S", kind: .gray) }
                        SetRow(title: "Mini timer", detail: nil, isLast: true) { Pill(text: "⇧⌘M", kind: .gray) }
                    }
                    privacyNote
                case .screenshots:
                    SetGroup(title: "Set by your organisation") {
                        SetRow("Capture screenshots", value: c.screenshotsEnabled ? "On" : "Off")
                        if c.screenshotsEnabled {
                            SetRow("Frequency", value: "Every \(Format.duration(c.screenshotIntervalSec))")
                            SetRow("Blur", value: "Radius \(c.blurRadius)")
                        }
                        SetRow(title: "Screen Recording permission", detail: nil, isLast: true) {
                            if let p = model.permissions {
                                Pill(text: p.screenRecording ? "Allowed" : "Not allowed — screenshots skipped", kind: p.screenRecording ? .ok : .wait)
                            } else {
                                Pill(text: "Unknown (agent offline)", kind: .gray)
                            }
                        }
                    }
                    Text("Only the active window is captured — never the whole screen — and images are blurred before they are saved or uploaded.")
                        .font(Typo.caption).foregroundStyle(Palette.textTertiary)
                }
            }
        }
        .task { await load() }
    }

    private var privacyNote: some View {
        Text("Keystrokes are counted, never recorded. Websites are stored as domains only. Nothing is captured unless you are tracking a task.")
            .font(Typo.caption).foregroundStyle(Palette.textTertiary)
    }

    private func load() async {
        config = .loading
        do { config = .loaded(try await environment.agentAPI.config()) } catch { config = .failed(DashboardViewModel.map(error)) }
    }
}

// MARK: - Notifications

struct NotificationSettingsPane: View {
    @AppStorage(Prefs.desktopNotifications) private var desktop = true
    @Environment(AppModel.self) private var model
    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var reminderInterval = Prefs.reminderIntervalMin

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SetGroup {
                SetToggleRow(title: "Leave status and other updates", detail: "Banner when new EffiLens notifications arrive", isOn: $desktop)
                SetRow("Tracking reminders", value: reminderInterval == 0 ? "Off" : "Every \(reminderInterval) min")
                SetRow("Idle alerts", value: "When the app is in the background", isLast: true)
            }
            SetGroup {
                SetRow(title: "macOS permission", detail: nil) { Pill(text: statusText.0, kind: statusText.1) }
                SetRow(title: status == .notDetermined ? "Allow notifications" : "System notification settings", detail: nil, isLast: true) {
                    if status == .notDetermined {
                        Button("Allow…") { Task { await DesktopNotifier.requestAuthorization(); await refresh() } }.buttonStyle(.effi)
                    } else {
                        Button("Open…") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
                        }
                        .buttonStyle(.effi)
                    }
                }
            }
            Text("Alert style and sounds are managed in System Settings › Notifications. Email preferences are managed in the web portal.")
                .font(Typo.caption).foregroundStyle(Palette.textTertiary)
        }
        .task { await refresh() }
    }

    private var statusText: (String, Pill.Kind) {
        switch status {
        case .authorized, .provisional: return ("Allowed", .ok)
        case .denied: return ("Denied", .no)
        case .notDetermined: return ("Not requested", .gray)
        @unknown default: return ("Unknown", .gray)
        }
    }

    private func refresh() async {
        status = await DesktopNotifier.authorizationStatus()
        reminderInterval = Prefs.reminderIntervalMin
    }
}

// MARK: - Appearance

struct AppearanceSettingsPane: View {
    @AppStorage(Prefs.appearance) private var appearance = "system"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SetGroup {
                SetRow(title: "Appearance", detail: nil) {
                    EffiSegmented(selection: $appearance, options: [("dark", "Dark"), ("light", "Light"), ("system", "Auto")])
                }
                SetRow(title: "Accent colour", detail: "Fixed by the EffiLens brand", isLast: true) {
                    HStack(spacing: 6) {
                        Circle().fill(Brand.portalGold).frame(width: 20, height: 20).help("Light mode accent")
                        Circle().fill(Brand.amber).frame(width: 20, height: 20).help("Dark mode accent")
                    }
                }
            }
        }
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
    @State private var newPassword = ""
    @State private var confirm = ""
    @State private var working = false
    @State private var message: Result<String, AppError>?
    @State private var confirmSignOut = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Card {
                HStack(spacing: 16) {
                    InitialsAvatar(initials: model.user?.initials ?? "?", size: 60)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.user?.displayName ?? "—").font(.system(size: 16, weight: .bold))
                        Text(model.role.displayName).font(Typo.body).foregroundStyle(Palette.textSecondary)
                        Text(model.user?.email ?? "").font(Typo.caption).foregroundStyle(Palette.textTertiary)
                    }
                }
            }
            .padding(.bottom, Space.l)
            SetGroup {
                SetRow("Organisation", value: model.user?.organizationName ?? "—")
                SetRow("Manager", value: profile?.managerName ?? "—")
                SetRow("Time zone", value: model.user?.timezone ?? "—")
                SetRow("Device", value: DeviceInfo.name, isLast: true)
            }
            SetGroup(title: "Change password") {
                VStack(alignment: .leading, spacing: 8) {
                    EffiTextField(placeholder: "Current password", text: $current, secure: true)
                    EffiTextField(placeholder: "New password (8+ characters)", text: $newPassword, secure: true)
                    EffiTextField(placeholder: "Confirm new password", text: $confirm, secure: true)
                    HStack {
                        switch message {
                        case .success(let text): Text(text).foregroundStyle(Palette.success)
                        case .failure(let error): Text(error.userMessage).foregroundStyle(Palette.danger)
                        case .none:
                            if !confirm.isEmpty, confirm != newPassword { Text("Passwords don't match.").foregroundStyle(Palette.danger) }
                        }
                        Spacer()
                        Button("Change Password") { Task { await changePassword() } }
                            .buttonStyle(.effi)
                            .disabled(working || current.isEmpty || newPassword.count < 8 || newPassword != confirm)
                    }
                    .font(.system(size: 12))
                }
                .padding(14)
            }
            HStack {
                Button("Sign Out") { confirmSignOut = true }.buttonStyle(.effiDanger)
                Text("Stops tracking and removes this account's unsynced activity from this Mac.")
                    .font(Typo.caption).foregroundStyle(Palette.textTertiary)
            }
        }
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
            _ = try await environment.profile.changePassword(ChangePasswordRequest(currentPassword: current, newPassword: newPassword))
            current = ""
            newPassword = ""
            confirm = ""
            message = .success("Password changed.")
        } catch {
            message = .failure(DashboardViewModel.map(error))
        }
    }
}

// MARK: - About & Diagnostics (prototype V.about; no tokens, no personal content)

struct AboutDiagnosticsView: View {
    @Environment(AppModel.self) private var model
    @State private var copied = false

    var body: some View {
        Page(maxWidth: 680) {
            Card(padding: 30) {
                VStack(spacing: 0) {
                    AppIconTile(size: 104)
                    Text("EffiLens").font(Typo.hero).padding(.top, 16)
                    Text("Version \(model.environment?.configuration.appVersion ?? "—") · Universal · development build (unsigned)")
                        .font(Typo.body).foregroundStyle(Palette.textSecondary)
                    HStack(spacing: 8) {
                        Button("Check for Updates") { UpdateDialog.present(version: model.environment?.configuration.appVersion ?? "—") }.buttonStyle(.effi)
                        Button(copied ? "Copied" : "Copy Diagnostics") { copy() }.buttonStyle(.effi)
                    }
                    .padding(.top, 16)
                }
                .frame(maxWidth: .infinity)
            }
            SetGroup(title: "Health") {
                SetRow(title: "Tracking agent", detail: nil) { Pill(text: agentText.0, kind: agentText.1) }
                SetRow(title: "Backend connectivity", detail: nil) {
                    if let sync = model.syncStatus {
                        Pill(text: sync.connected ? (model.environment?.configuration.apiOrigin.host() ?? "Connected") : "Unreachable", kind: sync.connected ? .ok : .no)
                    } else {
                        Pill(text: "Unknown", kind: .gray)
                    }
                }
                SetRow(title: "Sync queue", detail: nil) {
                    let pending = model.syncStatus?.pendingEvents
                    Pill(text: pending.map { "\($0) pending" } ?? "—", kind: (pending ?? 0) > 0 ? .wait : .ok)
                }
                SetRow(title: "Accessibility permission", detail: nil) { permissionPill(model.permissions?.accessibility) }
                SetRow(title: "Screen Recording permission", detail: nil) { permissionPill(model.permissions?.screenRecording) }
                SetRow(title: "Input Monitoring permission", detail: nil) { permissionPill(model.permissions?.inputMonitoring) }
                SetRow(title: "Last sync", detail: nil, isLast: true) {
                    Pill(text: model.syncStatus?.lastSync.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—", kind: .gray)
                }
            }
            SetGroup(title: "Maintenance") {
                SetRow(title: "Sync now", detail: "Upload queued activity immediately") {
                    Button("Sync") { Task { await model.runAgent { try await $0.syncNow() } } }.buttonStyle(.effi).disabled(!model.isAgentConnected)
                }
                SetRow(title: "Reconnect agent", detail: "Re-register the background agent with macOS") {
                    Button("Reconnect") { model.restartAgentConnection() }.buttonStyle(.effi)
                }
                SetRow(title: "Logs", detail: "Console.app → search “effilens”", isLast: true) {
                    Button("Open Console") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Console.app")) }.buttonStyle(.effi)
                }
            }
        }
    }

    private var agentText: (String, Pill.Kind) {
        switch model.agentLink {
        case .connected: return ("Running · \(model.syncStatus?.agentVersion ?? "connected")", .ok)
        case .legacyConflict: return ("Blocked — legacy agent running", .wait)
        case .unavailable: return ("Not reachable", .no)
        case .unknown: return ("Not started", .gray)
        }
    }

    private func permissionPill(_ value: Bool?) -> some View {
        Pill(text: value.map { $0 ? "Granted" : "Not granted" } ?? "Unknown", kind: value.map { $0 ? .ok : .wait } ?? .gray)
    }

    private func copy() {
        let config = model.environment?.configuration
        func flag(_ v: Bool?) -> String { v.map { $0 ? "yes" : "no" } ?? "?" }
        let text = """
        EffiLens \(config?.appVersion ?? "?") (\(config?.bundleIdentifier ?? "?"))
        macOS \(ProcessInfo.processInfo.operatingSystemVersionString) · \(DeviceInfo.chip)
        API host: \(config?.apiOrigin.host() ?? "?")
        Agent: \(agentText.0); registration: \(String(describing: model.agentRegistration))
        Queue: \(model.syncStatus?.pendingEvents ?? -1) pending; last result: \(model.syncStatus?.lastResult ?? "?")
        Permissions: AX=\(flag(model.permissions?.accessibility)) SR=\(flag(model.permissions?.screenRecording)) IM=\(flag(model.permissions?.inputMonitoring))
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
    }
}

// MARK: - Mini timer (prototype #mini: 300 pt, radius 18)

struct MiniTimerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        let state = model.timerState
        let running = state?.state == .running
        HStack(spacing: 12) {
            ProgressRing(progress: Double((state?.elapsedSecs ?? 0) % 60) / 60, lineWidth: 4, tint: running ? Palette.okFill : nil) { EmptyView() }
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 0) {
                Text(Format.clock(state?.elapsedSecs ?? 0)).font(Typo.timerCompact).monospacedDigit()
                Text(state?.task?.taskName ?? (model.isAgentConnected ? "No task selected" : "Agent offline"))
                    .font(Typo.caption).foregroundStyle(Palette.textTertiary).lineLimit(1)
            }
            Spacer(minLength: 4)
            ToolbarIconButton(symbol: running ? "pause.fill" : "play.fill", help: running ? "Pause" : "Start") {
                Task { await model.runAgent { try await $0.togglePlayPause() } }
            }
            .disabled(state?.task == nil)
            ToolbarIconButton(symbol: "stop.fill", help: "Stop") {
                Task { await model.runAgent { try await $0.stopTracking() } }
            }
            .disabled(state == nil || state?.state == .idle)
            Button { dismissWindow(id: SceneID.miniTimer) } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.textTertiary).frame(width: 20, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close mini timer")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 300)
        .background(.regularMaterial)
        .background(FloatingWindowConfigurator())
    }
}

/// Keeps the mini timer above other windows on every Space, rounded 18 pt.
struct FloatingWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.level = .floating
            window.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
            window.isMovableByWindowBackground = true
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.contentView?.wantsLayer = true
            window.contentView?.layer?.cornerRadius = 18
            window.contentView?.layer?.masksToBounds = true
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
        alert.informativeText = "You're running EffiLens \(version) (development build).\n\nAutomatic updates for the native Mac app are not available yet. New versions are distributed as DMG/PKG installers by your administrator."
        alert.icon = NSApplication.shared.applicationIconImage
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
