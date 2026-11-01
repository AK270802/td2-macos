import SwiftUI
import EffiLensKit

/// Signature element of the dashboard: the live session ring, driven by the
/// local agent's real timer state (never simulated).
struct ActiveSessionCard: View {
    @Environment(AppModel.self) private var model
    let onOpenTracker: () -> Void

    /// Visual goal for the ring: one 8-hour working day (presentation only).
    private let ringGoalSec = 8 * 3600

    var body: some View {
        Card("Active session") {
            switch model.agentLink {
            case .connected(let state):
                connected(state)
            case .legacyConflict:
                ContentUnavailableView {
                    Label("Older EffiLens app is running", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("Quit it to track time here. Running both would record your time twice.")
                }
            case .unavailable, .unknown:
                ContentUnavailableView {
                    Label("Tracking agent offline", systemImage: "bolt.horizontal.circle")
                } description: {
                    Text("Time tracking starts once the EffiLens agent is running.")
                }
            }
        }
    }

    @ViewBuilder
    private func connected(_ state: AgentTimerState) -> some View {
        HStack(spacing: Space.xl) {
            ProgressRing(progress: Double(state.elapsedSecs) / Double(ringGoalSec), lineWidth: 10, tint: tint(for: state.state)) {
                VStack(spacing: Space.xxs) {
                    Text(Format.clock(state.elapsedSecs))
                        .font(.system(size: 20, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(phaseLabel(state)).font(Typo.caption).foregroundStyle(Palette.textSecondary)
                }
            }
            .frame(width: 140, height: 140)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(phaseLabel(state)), \(Format.duration(state.elapsedSecs)) elapsed")

            VStack(alignment: .leading, spacing: Space.s) {
                if let task = state.task {
                    Text(task.taskName).font(Typo.heading).lineLimit(2)
                    Text(task.projectName).font(Typo.caption).foregroundStyle(Palette.textSecondary)
                } else {
                    Text("No task selected").font(Typo.heading)
                    Text("Choose a task to start tracking.").font(Typo.caption).foregroundStyle(Palette.textSecondary)
                }
                if state.inMeeting { StatusPill(text: "In a meeting", tone: .info) }
                HStack {
                    Button(state.state == .running ? "Pause" : "Resume") {
                        Task { try? await model.environment?.agent?.togglePlayPause() }
                    }
                    .disabled(state.task == nil && state.state == .idle)
                    Button("Stop") {
                        Task { try? await model.environment?.agent?.stopTracking() }
                    }
                    .disabled(state.state == .idle)
                }
                .controlSize(.small)
                Button("Open Time Tracker", action: onOpenTracker).buttonStyle(.link).font(Typo.caption)
            }
        }
    }

    private func phaseLabel(_ state: AgentTimerState) -> String {
        switch state.state {
        case .running: return "Recording"
        case .paused: return "Paused"
        case .onBreak: return state.breakType.map { "On \($0)" } ?? "On break"
        case .idle: return "Ready"
        }
    }

    private func tint(for phase: AgentTimerState.Phase) -> Color {
        switch phase {
        case .running: return Palette.success
        case .paused, .onBreak: return Palette.warning
        case .idle: return Palette.accent
        }
    }
}
