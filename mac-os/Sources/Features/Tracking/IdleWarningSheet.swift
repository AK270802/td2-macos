import SwiftUI
import EffiLensKit

/// Idle warning — same behaviour as the Tauri `IdleWarning` window and the
/// go-agent prompt: 60 s countdown ring; "I'm still working" keeps the timer
/// running (idle span recorded as idle); "I'm on a break" — or no answer —
/// stops the session back-dated to when activity stopped (agent rules in
/// `common::timer_service::idle_auto_stop`).
struct IdleWarningSheet: View {
    @Environment(AppModel.self) private var model
    let startedAt: Date
    static let countdownSecs = 60
    @State private var acted = false

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            let elapsed = Int(context.date.timeIntervalSince(startedAt))
            let remaining = max(0, Self.countdownSecs - elapsed)
            content(remaining: remaining)
                .onChange(of: remaining) { _, value in
                    if value == 0 { respond(keepWorking: false, timedOut: true) }
                }
        }
        .padding(26)
        .frame(width: 400)
        .background(Palette.surfaceRaised)
        .interactiveDismissDisabled()
    }

    private func content(remaining: Int) -> some View {
        let idleFor = model.timerState?.idleSinceSecs ?? 0
        let urgent = remaining <= 10
        return VStack(spacing: 0) {
            Text("INACTIVITY DETECTED").font(.system(size: 10.5, weight: .semibold)).tracking(1.6).foregroundStyle(Palette.accentText)
            ZStack {
                ProgressRing(progress: Double(remaining) / Double(Self.countdownSecs), lineWidth: 4, tint: urgent ? Palette.redFill : nil) { EmptyView() }
                Text("\(remaining)").font(.system(size: 21, weight: .bold, design: .monospaced))
                    .foregroundStyle(urgent ? Palette.danger : Palette.textPrimary)
            }
            .frame(width: 74, height: 74)
            .padding(.top, 14)
            Text("Are you still working?").font(Typo.serif(24)).padding(.top, 12)
            Text("No input for \(Format.duration(idleFor)). Unanswered, this session pauses and the idle time is excluded.")
                .font(Typo.body).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)
            HStack(spacing: 10) {
                Button("I'm on a Break") { respond(keepWorking: false) }
                    .buttonStyle(.effiButton(.normal, .large, fullWidth: true))
                Button("I'm Still Working") { respond(keepWorking: true) }
                    .buttonStyle(.effiButton(.primary, .large, fullWidth: true))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 18)
            .disabled(acted)
        }
        .accessibilityElement(children: .contain)
    }

    private func respond(keepWorking: Bool, timedOut: Bool = false) {
        guard !acted else { return }
        acted = true
        Task { await model.respondToIdle(keepWorking: keepWorking, timedOut: timedOut) }
    }
}
