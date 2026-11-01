import AppKit
import SwiftUI
import EffiLensKit

/// Menu-bar label: compact live timer with a state dot (prototype menu-bar extra).
struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let state = model.timerState, state.state != .idle {
            HStack(spacing: 4) {
                Image(systemName: state.state == .running ? "record.circle.fill" : "pause.circle.fill")
                Text(Format.clock(state.elapsedSecs)).monospacedDigit()
            }
        } else {
            Image(systemName: "timer")
        }
    }
}

/// Menu-bar popover (prototype: 330 pt popover with timer, quick stats, actions).
struct MenuBarPopover: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.s) {
                BrandMark(size: 22)
                Text("EffiLens").font(Typo.heading)
                Spacer()
                SyncIndicator()
            }

            timerCard

            Divider()

            Button("Open Dashboard…") {
                openWindow(id: SceneID.main)
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("o")
            if model.phase != .ready {
                Text("Sign in from the main window to start tracking.").font(Typo.caption).foregroundStyle(Palette.textSecondary)
            }
            Divider()
            Button("Quit EffiLens") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.plain)
        .padding(Space.l)
        .frame(width: 330)
    }

    @ViewBuilder
    private var timerCard: some View {
        if let state = model.timerState {
            VStack(alignment: .leading, spacing: Space.s) {
                Text(Format.clock(state.elapsedSecs))
                    .font(.system(size: 34, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                Text(state.task?.taskName ?? "No task selected")
                    .font(Typo.body).foregroundStyle(Palette.textSecondary).lineLimit(1)
                HStack {
                    Button(state.state == .running ? "Pause" : "Start") {
                        Task { try? await model.environment?.agent?.togglePlayPause() }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Stop") {
                        Task { try? await model.environment?.agent?.stopTracking() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(state.state == .idle)
                }
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.inset, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        } else {
            Label(model.agentLink == .legacyConflict ? "Older EffiLens app is running" : "Tracking agent offline",
                  systemImage: "bolt.horizontal.circle")
                .font(Typo.body)
                .foregroundStyle(Palette.textSecondary)
        }
    }
}

/// Settings scene shell — panes arrive in Milestone 7.
struct SettingsPlaceholderView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("Signed in as", value: model.user?.email ?? "Not signed in")
                LabeledContent("Role", value: model.user.map { $0.roleValue.displayName } ?? "—")
                LabeledContent("Server", value: model.environment?.configuration.apiOrigin.host() ?? "—")
            }
            Section {
                Text("General, Tracking, Screenshots, Notifications and Appearance settings arrive in Milestone 7.")
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 320)
    }
}
