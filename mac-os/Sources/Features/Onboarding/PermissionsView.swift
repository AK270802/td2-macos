import SwiftUI
import AppKit
import ApplicationServices
import CoreGraphics
import IOKit.hid
import EffiLensKit

/// macOS privacy permissions used by tracking. Requests always go through the
/// system prompt / System Settings — never bypassed. Status shown is what the
/// agent itself reports (it is the process that captures), falling back to the
/// app's own preflight when the agent is offline.
struct PermissionsView: View {
    @Environment(AppModel.self) private var model
    @State private var local = LocalPermissions.current()
    var onDone: (() -> Void)?

    private var agentPermissions: AgentPermissions? { model.permissions }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Permissions").font(Typo.title)
                Text("EffiLens only captures while you are tracking time. Each permission can be changed later in System Settings.")
                    .font(Typo.body).foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PermissionRow(
                title: "Accessibility",
                detail: "Reads the title of the window you're working in.",
                symbol: "accessibility",
                granted: agentPermissions?.accessibility ?? local.accessibility,
                request: {
                    LocalPermissions.requestAccessibility()
                    LocalPermissions.openSettings(pane: "Privacy_Accessibility")
                }
            )
            PermissionRow(
                title: "Screen Recording",
                detail: "Takes blurred screenshots of the active window only — never the whole screen.",
                symbol: "rectangle.dashed.badge.record",
                granted: agentPermissions?.screenRecording ?? local.screenRecording,
                request: {
                    LocalPermissions.requestScreenRecording()
                    LocalPermissions.openSettings(pane: "Privacy_ScreenCapture")
                }
            )
            PermissionRow(
                title: "Input Monitoring",
                detail: "Counts keyboard and mouse activity. What you type is never read or stored.",
                symbol: "keyboard",
                granted: agentPermissions?.inputMonitoring ?? local.inputMonitoring,
                request: {
                    LocalPermissions.requestInputMonitoring()
                    LocalPermissions.openSettings(pane: "Privacy_ListenEvent")
                }
            )

            if model.agentRegistration == .requiresApproval {
                Label("Allow “EffiLens” in Login Items so the tracking agent can run.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Palette.warning)
                Button("Open Login Items") { AgentLifecycle.openLoginItemsSettings() }
            }

            HStack {
                Button("Refresh") { refresh() }
                Spacer()
                if let onDone { Button("Continue", action: onDone).buttonStyle(.borderedProminent) }
            }
        }
        .padding(Space.xxl)
        .frame(maxWidth: 560)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh() {
        local = LocalPermissions.current()
        Task { await model.refreshPermissions() }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let symbol: String
    let granted: Bool
    let request: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(Palette.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(title).font(Typo.bodyEmphasis)
                Text(detail).font(Typo.caption).foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if granted {
                StatusPill(text: "Allowed", tone: .success)
            } else {
                Button("Allow…", action: request)
            }
        }
        .padding(Space.m)
        .background(Palette.inset, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
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
                Button("Review…") { showSheet = true }
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.s)
            .background(Palette.warning.opacity(0.12))
            .sheet(isPresented: $showSheet) {
                PermissionsView(onDone: { showSheet = false })
                    .environment(model)
            }
        }
    }
}
