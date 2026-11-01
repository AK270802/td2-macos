import AppKit
import SwiftUI
import EffiLensKit

/// Menu-bar label (prototype `.mb-extra`): state dot + mono timer while a
/// session exists, otherwise the timer glyph.
struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    var showsTimer = true

    var body: some View {
        label
            // The menu-bar label is always alive, so it provides the
            // "reopen main window" action used by idle / reminder / wake.
            .onAppear { model.openMainWindowAction = { openWindow(id: SceneID.main) } }
    }

    @ViewBuilder
    private var label: some View {
        if showsTimer, let state = model.timerState, state.state != .idle {
            HStack(spacing: 4) {
                Image(systemName: state.state == .running ? "circle.fill" : "pause.circle")
                Text(Format.clock(state.elapsedSecs)).font(.system(size: 12, design: .monospaced)).monospacedDigit()
            }
        } else {
            Image(systemName: "timer")
        }
    }
}

/// Menu-bar popover (prototype `#popover`, 330 pt): header with connection
/// pill, timer card, Today / Leave-left cards, recent tasks, menu rows.
struct MenuBarPopover: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var stats: AgentLocalTimeStats?
    @State private var leaveLeft: String?
    @State private var recent: [TaskChoice] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                BrandLogoTile(size: 22)
                Text("EffiLens").font(Typo.bodyEmphasis)
                Spacer()
                connectionPill
            }

            timerCard.padding(.top, 12)

            if model.phase == .ready {
                EqualColumns(count: 2, spacing: 8) {
                    smallCard("Today", stats.map { Format.duration($0.workedTodaySec) } ?? "—")
                    smallCard("Leave left", leaveLeft ?? "—")
                }
                .padding(.top, 10)

                if !recent.isEmpty {
                    Text("Recent tasks").font(Typo.small).foregroundStyle(Palette.textTertiary).padding(.top, 12).padding(.bottom, 4)
                    ForEach(recent) { choice in
                        menuRow(choice.task.name, dot: IdentityColor.color(for: choice.project.id)) { model.track(choice) }
                            .disabled(!model.isAgentConnected)
                    }
                }
            } else {
                Text("Sign in from the main window to start tracking.").font(Typo.caption).foregroundStyle(Palette.textSecondary).padding(.top, 10)
            }

            if let error = model.agentCommandError {
                Text(error.userMessage).font(Typo.caption).foregroundStyle(Palette.warning).padding(.top, 8)
            }

            Divider().overlay(Palette.hairline).padding(.vertical, 8)
            if model.timerState?.state == .running {
                menuRow("Take a 15-min Break") { Task { await model.startCoffeeBreak() } }
            } else if model.timerState?.state == .onBreak {
                menuRow("End Break") { Task { await model.runAgent { try await $0.togglePlayPause() } } }
            }
            menuRow("Open Dashboard…") { open(.dashboard) }
            if let portal = model.environment?.configuration.portalOrigin {
                menuRow("Open Web Portal…") { NSWorkspace.shared.open(portal) }
            }
            menuRow("Apply for Leave…") { open(.applyLeave) }.disabled(model.phase != .ready)
            menuRow("Toggle Mini Timer") { openWindow(id: SceneID.miniTimer) }
            SettingsLink { menuLabel("Settings…") }.buttonStyle(.plain)
            menuRow("Quit EffiLens") { NSApp.terminate(nil) }
        }
        .padding(14)
        .frame(width: 330)
        .task { await loadExtras() }
    }

    private var connectionPill: some View {
        Group {
            switch model.agentLink {
            case .connected:
                if model.syncStatus?.connected == false { Pill(text: "Offline", kind: .no) } else { Pill(text: "Connected", kind: .ok) }
            case .legacyConflict: Pill(text: "Legacy app running", kind: .wait)
            case .unavailable, .unknown: Pill(text: "Agent offline", kind: .gray)
            }
        }
    }

    private var timerCard: some View {
        let state = model.timerState
        let running = state?.state == .running
        return Card(padding: 18) {
            VStack(spacing: 2) {
                Text(Format.clock(state?.elapsedSecs ?? 0)).font(Typo.timerMedium).monospacedDigit()
                Text(state?.task?.taskName ?? (model.isAgentConnected ? "No task selected" : "Tracking agent offline"))
                    .font(Typo.caption).foregroundStyle(Palette.textTertiary).lineLimit(1)
                HStack(spacing: 8) {
                    Button {
                        Task { await model.runAgent { try await $0.togglePlayPause() } }
                    } label: {
                        Label(running ? "Pause" : "Start", systemImage: running ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.effiButton(running ? .normal : .primary))
                    .disabled(state?.task == nil)
                    Button("Stop") { Task { await model.runAgent { try await $0.stopTracking() } } }
                        .buttonStyle(.effi)
                        .disabled(state == nil || state?.state == .idle)
                }
                .padding(.top, 12)
                .disabled(!model.isAgentConnected)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func smallCard(_ label: String, _ value: String) -> some View {
        Card(padding: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 10.5)).foregroundStyle(Palette.textTertiary)
                Text(value).font(.system(size: 13, weight: .bold, design: .monospaced))
            }
        }
    }

    private func menuLabel(_ title: String, dot: Color? = nil) -> some View {
        HStack(spacing: 9) {
            if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
            Text(title).font(Typo.body).foregroundStyle(Palette.textPrimary).lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
    }

    private func menuRow(_ title: String, dot: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) { menuLabel(title, dot: dot) }
            .buttonStyle(MenuRowButtonStyle())
    }

    private func open(_ route: Route) {
        model.requestedRoute = route
        openWindow(id: SceneID.main)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func loadExtras() async {
        guard model.phase == .ready, let environment = model.environment else { return }
        if model.isAgentConnected { stats = try? await environment.agent?.localTimeStats() }
        if let b = try? await environment.leave.balance() {
            leaveLeft = "\(b.totalRemainingText) days"
        }
        if let projects = try? await environment.work.assignedProjects() {
            recent = Array(TaskChoice.all(projects).prefix(3))
        }
    }
}

private struct MenuRowButtonStyle: ButtonStyle {
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(hovering && isEnabled ? Palette.textPrimary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .onHover { hovering = $0 }
            .opacity(isEnabled ? 1 : 0.4)
    }
}
