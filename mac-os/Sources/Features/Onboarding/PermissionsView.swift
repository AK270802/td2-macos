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
/// Status is what the agent reports (it is the capturing process), falling
/// back to the app's own preflight when the agent is offline.
struct PermissionsList: View {
    @Environment(AppModel.self) private var model
    @State private var local = LocalPermissions.current()
    @State private var notifications: UNAuthorizationStatus = .notDetermined

    var body: some View {
        VStack(spacing: 8) {
            PermissionRow(title: "Notifications", detail: "Tracking reminders and leave updates", symbol: "bell",
                          granted: notifications == .authorized || notifications == .provisional) {
                Task {
                    if notifications == .denied {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
                    } else {
                        await DesktopNotifier.requestAuthorization()
                    }
                    await refresh()
                }
            }
            PermissionRow(title: "Accessibility", detail: "Detect the active app and window title for accurate time", symbol: "hand.raised",
                          granted: model.permissions?.accessibility ?? local.accessibility) {
                LocalPermissions.requestAccessibility()
                LocalPermissions.openSettings(pane: "Privacy_Accessibility")
            }
            PermissionRow(title: "Screen Recording", detail: "Optional — blurred active-window screenshots if your organisation enables them", symbol: "rectangle.dashed",
                          granted: model.permissions?.screenRecording ?? local.screenRecording) {
                LocalPermissions.requestScreenRecording()
                LocalPermissions.openSettings(pane: "Privacy_ScreenCapture")
            }
            PermissionRow(title: "Input Monitoring", detail: "Counts keyboard and mouse activity — never what you type", symbol: "keyboard",
                          granted: model.permissions?.inputMonitoring ?? local.inputMonitoring) {
                LocalPermissions.requestInputMonitoring()
                LocalPermissions.openSettings(pane: "Privacy_ListenEvent")
            }
            PermissionRow(title: "Open at Login", detail: loginDetail, symbol: "person.crop.circle.badge.checkmark",
                          granted: model.agentRegistration == .enabled,
                          actionTitle: model.agentRegistration == .notBundled ? nil : "Allow…") {
                model.restartAgentConnection()
                if model.agentRegistration == .requiresApproval { AgentLifecycle.openLoginItemsSettings() }
            }
            Text("Browser domains: macOS asks once per browser (Automation) the first time you track with it in front.")
                .font(Typo.caption).foregroundStyle(Palette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        }
        .task { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refresh() }
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
    let granted: Bool
    var actionTitle: String? = "Allow…"
    let request: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, tint: Palette.blueFill)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Typo.bodyEmphasis).foregroundStyle(Palette.textPrimary)
                Text(detail).font(Typo.caption).foregroundStyle(Palette.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s)
            if granted {
                Pill(text: "Allowed", kind: .ok, symbol: "checkmark")
            } else if let actionTitle {
                Button(actionTitle, action: request).buttonStyle(.effi)
            } else {
                Pill(text: "Unavailable", kind: .gray)
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .background(Palette.textPrimary.opacity(0.02), in: RoundedRectangle(cornerRadius: Radius.task, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.task, style: .continuous).strokeBorder(Palette.hairline))
        .accessibilityElement(children: .combine)
        .accessibilityValue(granted ? "Allowed" : "Not allowed")
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
