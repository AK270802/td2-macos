import SwiftUI
import AppKit
import ApplicationServices
import CoreGraphics
import IOKit.hid
import UserNotifications
import EffiLensKit

/// macOS privacy permissions (prototype `.perm` rows: 32 pt blue icon tile,
/// title, dim description, `Allow…` or a green "Allowed" pill). Requests
/// always go through the system prompt / System Settings — never bypassed.
///
/// Two TCC identities are involved: EffiLens.app (prompts, UI) and the
/// tracking agent `effilens-agentd`, which launchd runs as its OWN
/// responsible process — so macOS checks the agent's identity when it
/// captures. A grant for "EffiLens" alone does not authorise capture.
/// `PermissionState` combines both so the row never shows `Allow…` for
/// something that is granted, nor "Allowed" while capture would fail.
struct PermissionsList: View {
    @Environment(AppModel.self) private var model
    @State private var local = LocalPermissions.current()
    @State private var notifications: UNAuthorizationStatus = .notDetermined

    var body: some View {
        VStack(spacing: 8) {
            PermissionRow(title: "Notifications", detail: "Tracking reminders and leave updates", symbol: "bell",
                          state: notifications == .authorized || notifications == .provisional ? .granted : .notGranted) {
                Task {
                    if notifications == .denied {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
                    } else {
                        await DesktopNotifier.requestAuthorization()
                    }
                    await refresh()
                }
            }
            PermissionRow(title: "Accessibility", detail: "Detect the active app for accurate time", symbol: "hand.raised",
                          state: PermissionState(app: local.accessibility, agent: model.permissions?.accessibility)) {
                request(pane: "Privacy_Accessibility") { LocalPermissions.requestAccessibility() }
            }
            PermissionRow(title: "Screen Recording", detail: "Optional, for policy screenshots", symbol: "rectangle.dashed",
                          state: PermissionState(app: local.screenRecording, agent: model.permissions?.screenRecording)) {
                request(pane: "Privacy_ScreenCapture") { LocalPermissions.requestScreenRecording() }
            }
            PermissionRow(title: "Input Monitoring", detail: "Activity counts — never what you type", symbol: "keyboard",
                          state: PermissionState(app: local.inputMonitoring, agent: model.permissions?.inputMonitoring)) {
                request(pane: "Privacy_ListenEvent") { LocalPermissions.requestInputMonitoring() }
            }
            PermissionRow(title: "Open at Login", detail: loginDetail, symbol: "person.crop.circle.badge.checkmark",
                          state: model.agentRegistration == .enabled ? .granted : .notGranted,
                          actionTitle: model.agentRegistration == .notBundled ? nil : "Allow…") {
                model.restartAgentConnection()
                if model.agentRegistration == .requiresApproval { AgentLifecycle.openLoginItemsSettings() }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(footnote)
                    .font(Typo.caption).foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.s)
                Button("Recheck") { Task { await refresh() } }
                    .buttonStyle(.effi)
                    .controlSize(.small)
            }
            .padding(.top, 2)
        }
        .task {
            // Initial check, then poll while visible: TCC changes made in
            // System Settings post no notification to the app.
            await refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refresh() }
        }
    }

    private var footnote: String {
        let states = [
            PermissionState(app: local.accessibility, agent: model.permissions?.accessibility),
            PermissionState(app: local.screenRecording, agent: model.permissions?.screenRecording),
            PermissionState(app: local.inputMonitoring, agent: model.permissions?.inputMonitoring),
        ]
        if states.contains(.agentPending) {
            return "In System Settings, turn on both “EffiLens” and “effilens-agentd”. If a switch is already on, select it, remove it with −, then click Enable again."
        }
        return "Browsers: macOS asks once per browser for website domains."
    }

    /// App request (prompt attributed to EffiLens) + agent request (adds the
    /// capturing process to the list), then the matching Settings pane.
    private func request(pane: String, appRequest: () -> Void) {
        appRequest()
        Task {
            await model.requestAgentPermissions()
            LocalPermissions.openSettings(pane: pane)
        }
    }

    private var loginDetail: String {
        switch model.agentRegistration {
        case .requiresApproval: return "Allow EffiLens under System Settings › General › Login Items"
        case .notBundled: return "The tracking agent is not included in this build"
        case .failed(let message): return "Couldn't register the agent: \(message)"
        default: return "Start the tracking agent automatically"
        }
    }

    private func refresh() async {
        local = LocalPermissions.current()
        notifications = await DesktopNotifier.authorizationStatus()
        await model.refreshPermissions()
    }
}

/// Sheet wrapper used from the main window's permission banner.
struct PermissionsView: View {
    var onDone: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            OnboardingHeading(prefix: "A few ", emphasis: "permissions", subtitle: "EffiLens only captures while you are tracking time.")
            PermissionsList()
            HStack {
                Spacer()
                if let onDone { Button("Done", action: onDone).buttonStyle(.effiPrimary).keyboardShortcut(.defaultAction) }
            }
        }
        .padding(28)
        .frame(width: 520)
        .background(Palette.surfaceRaised)
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let symbol: String
    let state: PermissionState
    var actionTitle: String? = "Allow…"
    let request: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, tint: Palette.blueFill)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Typo.bodyEmphasis).foregroundStyle(Palette.textPrimary)
                Text(detail).font(Typo.caption).foregroundStyle(Palette.textTertiary).lineLimit(1)
            }
            Spacer(minLength: Space.s)
            if state == .granted {
                Pill(text: "Allowed", kind: .ok, symbol: "checkmark")
            } else if state == .agentPending, actionTitle != nil {
                Button("Enable agent…", action: request).buttonStyle(.effi)
                    .help("EffiLens is allowed; the tracking agent (effilens-agentd) also needs this permission.")
            } else if let actionTitle {
                Button(actionTitle, action: request).buttonStyle(.effi)
            } else {
                Pill(text: "Unavailable", kind: .gray)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Palette.textPrimary.opacity(0.02), in: RoundedRectangle(cornerRadius: Radius.task, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.task, style: .continuous).strokeBorder(Palette.hairline))
        .accessibilityElement(children: .combine)
        .accessibilityValue(state.accessibilityText)
    }
}

/// Combined status of one capture permission.
enum PermissionState: Equatable {
    /// The capturing agent is authorised (or, with the agent unreachable,
    /// the app is — the agent re-checks when it starts capturing).
    case granted
    /// EffiLens.app is authorised but the agent is not yet.
    case agentPending
    case notGranted

    init(app: Bool, agent: Bool?) {
        switch agent {
        case .some(true): self = .granted
        case .some(false): self = app ? .agentPending : .notGranted
        case .none: self = app ? .granted : .notGranted   // agent unknown: never reported as denied on its own
        }
    }

    var accessibilityText: String {
        switch self {
        case .granted: return "Allowed"
        case .agentPending: return "Allowed for EffiLens, tracking agent not yet allowed"
        case .notGranted: return "Not allowed"
        }
    }
}

/// The app process's own view of TCC (prompts are attributed to the app).
struct LocalPermissions: Equatable {
    var accessibility: Bool
    var screenRecording: Bool
    var inputMonitoring: Bool

    static func current() -> LocalPermissions {
        LocalPermissions(
            accessibility: AXIsProcessTrusted(),
            screenRecording: CGPreflightScreenCaptureAccess(),
            inputMonitoring: IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        )
    }

    static func requestAccessibility() {
        // "AXTrustedCheckOptionPrompt" == kAXTrustedCheckOptionPrompt (avoids an unmanaged C global).
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
    }

    static func requestInputMonitoring() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    static func openSettings(pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Slim banner in the main window when the agent lacks a permission.
struct PermissionsBanner: View {
    @Environment(AppModel.self) private var model
    @State private var showSheet = false

    private var missing: [String] {
        guard let p = model.permissions else { return [] }
        var names: [String] = []
        if !p.accessibility { names.append("Accessibility") }
        if !p.screenRecording { names.append("Screen Recording") }
        if !p.inputMonitoring { names.append("Input Monitoring") }
        return names
    }

    var body: some View {
        if !missing.isEmpty || model.agentRegistration == .requiresApproval {
            HStack(spacing: Space.m) {
                Image(systemName: "lock.shield").foregroundStyle(Palette.warning)
                Text(model.agentRegistration == .requiresApproval
                     ? "Allow EffiLens in Login Items to enable tracking."
                     : "Tracking is limited: \(missing.joined(separator: ", ")) not allowed.")
                    .font(Typo.body)
                Spacer()
                Button("Review…") { showSheet = true }.buttonStyle(.effi)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 9)
            .background(Palette.warning.opacity(0.12))
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.warning.opacity(0.3)).frame(height: 1) }
            .sheet(isPresented: $showSheet) {
                PermissionsView(onDone: { showSheet = false })
                    .environment(model)
            }
        }
    }
}
