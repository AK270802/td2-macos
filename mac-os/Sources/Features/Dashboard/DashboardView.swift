import SwiftUI
import EffiLensKit

/// Dashboard — prototype `V.dashboard`: date overline + hero greeting +
/// large primary action; 4 KPI cards; Active session (1.25 fr) + Weekly
/// hours; Recent sessions · Leave balance · Upcoming. Real data only.
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var viewModel: DashboardViewModel
    let onNavigate: (Route) -> Void

    init(environment: AppEnvironment, onNavigate: @escaping (Route) -> Void) {
        _viewModel = State(initialValue: DashboardViewModel(environment: environment))
        self.onNavigate = onNavigate
    }

    var body: some View {
        Page {
            hero.padding(.bottom, 6)
            EqualColumns(count: 4) { kpis }
            FractionalColumns(ratio: 1.25) {
                activeSession
                weeklyHours
            }
            EqualColumns(count: 3) {
                recentSessions
                leaveBalance
                upcoming
            }
        }
        .task { await viewModel.load() }
        .background(KeyboardShortcutButton(key: "r") { Task { await viewModel.load() } })
    }

    // MARK: Hero

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning, "
        case 12..<17: return "Good afternoon, "
        default: return "Good evening, "
        }
    }

    private var firstName: String {
        model.user?.displayName.split(separator: " ").first.map(String.init) ?? "there"
    }

    private var hero: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Overline(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                HeroTitle(prefix: greeting, emphasis: firstName, suffix: ".")
            }
            Spacer()
            if model.timerState?.state == .running {
                Button { Task { await model.runAgent { try await $0.togglePlayPause() } } } label: { Label("Pause", systemImage: "pause.fill") }
                    .buttonStyle(.effiButton(.primary, .large))
            } else {
                Button { onNavigate(.tracker) } label: { Label("Start Tracking", systemImage: "play.fill") }
                    .buttonStyle(.effiButton(.primary, .large))
            }
        }
    }

    // MARK: KPIs

    @ViewBuilder
    private var kpis: some View {
        kpiCard("Today", symbol: "clock", state: viewModel.today) { s in
            StatTileBody(value: Format.duration(s.workedSec), footnote: "\(s.utilisationPct)% utilisation")
        }
        kpiCard("This week", symbol: "chart.bar", state: viewModel.week) { w in
            StatTileBody(value: Format.hours(w.workedSec),
                         suffix: w.requiredSec.map { "/ \(Format.hours($0, fractionDigits: 0))h" } ?? "h",
                         progress: w.requiredSec.map { Double(w.workedSec) / Double($0) })
        }
        kpiCard("Productivity", symbol: "eye", state: viewModel.today) { s in
            StatTileBody(value: "\(s.productivePct)", suffix: "%", footnote: "Today")
        }
        kpiCard("Leave left", symbol: "leaf", state: viewModel.balance) { b in
            StatTileBody(value: Format.days(FlexibleDecimal((b.paidRemaining?.value ?? 0) + (b.compOffRemaining?.value ?? 0))),
                         suffix: "days",
                         footnote: viewModel.pendingLeaveCount.map { $0 == 0 ? "No pending requests" : "\($0) request\($0 == 1 ? "" : "s") pending" })
        }
    }

    private func kpiCard<V, C: View>(_ title: String, symbol: String, state: Loadable<V>, @ViewBuilder content: @escaping (V) -> C) -> some View {
        Card(title, symbol: symbol) {
            switch state {
            case .idle, .loading:
                KPIText(value: "0h 00m").redacted(reason: .placeholder)
            case .failed:
                Text("Unavailable").font(Typo.caption).foregroundStyle(Palette.textTertiary).frame(height: 32, alignment: .leading)
            case .loaded(let value):
                content(value)
            }
        }
    }

    // MARK: Active session

    private var dailyGoal: Int {
        viewModel.week.value?.requiredSec.map { $0 / 5 } ?? 8 * 3600
    }

    private var sessionPill: AnyView {
        if model.timerState?.state == .running { return AnyView(Pill(text: "● Live", kind: .ok)) }
        return AnyView(Pill(text: model.isAgentConnected ? "Idle" : "Agent offline", kind: .gray))
    }

    private var activeSession: some View {
        let state = model.timerState
        let todaySec = viewModel.today.value?.workedSec ?? 0
        let running = state?.state == .running
        return Card("Active session", trailing: sessionPill) {
            HStack(spacing: 22) {
                ProgressRing(progress: Double(todaySec + (running ? (state?.elapsedSecs ?? 0) : 0)) / Double(max(dailyGoal, 1)), lineWidth: 11) {
                    VStack(spacing: 2) {
                        Text(Format.clock(state?.elapsedSecs ?? 0)).font(.system(size: 20, weight: .semibold, design: .monospaced)).monospacedDigit()
                        Text("of \(Format.hours(dailyGoal, fractionDigits: 0))h goal").font(.system(size: 10.5)).foregroundStyle(Palette.textTertiary)
                    }
                }
                .frame(width: 140, height: 140)
                VStack(alignment: .leading, spacing: 0) {
                    Text(state?.task?.projectName ?? "No task selected").font(Typo.small).foregroundStyle(Palette.textTertiary)
                    Text(state?.task?.taskName ?? "Choose a task to begin").font(.system(size: 17, weight: .semibold)).lineLimit(2)
                        .padding(.top, 3).padding(.bottom, 12)
                    HStack(spacing: 8) {
                        if state?.task != nil {
                            Button { Task { await model.runAgent { try await $0.togglePlayPause() } } } label: {
                                Label(running ? "Pause" : "Resume", systemImage: running ? "pause.fill" : "play.fill")
                            }
                            .buttonStyle(.effiButton(running ? .normal : .primary))
                            Button("Stop") { Task { await model.runAgent { try await $0.stopTracking() } } }.buttonStyle(.effi)
                        } else {
                            Button { onNavigate(.tasks) } label: { Label("Select Task", systemImage: "play.fill") }.buttonStyle(.effiPrimary)
                        }
                        Button("Mini Timer") { openWindow(id: SceneID.miniTimer) }.buttonStyle(.effi)
                    }
                    .disabled(!model.isAgentConnected)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Weekly hours

    private var weeklyHours: some View {
        Card("Weekly hours") {
            LoadStateView(state: viewModel.weeklyActivity, emptyTitle: "No activity this week", emptySymbol: "chart.bar",
                          isEmpty: { $0.isEmpty }, retry: { Task { await viewModel.loadWeeklyActivity() } }) { days in
                BarsChart(bars: Self.bars(for: days), maxValue: max(9, days.map { Double($0.activeSec) / 3600 }.max() ?? 9))
            }
        }
    }

    private static func bars(for days: [UtilisationDay]) -> [BarsChart.Bar] {
        let today = CalendarDate(Date())
        return days.map { day in
            let hours = Double(day.activeSec) / 3600
            return BarsChart.Bar(label: day.date.date()?.formatted(.dateTime.weekday(.abbreviated)) ?? "",
                                 value: hours,
                                 valueText: day.activeSec > 0 ? hours.formatted(.number.precision(.fractionLength(1))) : "",
                                 highlighted: day.date == today)
        }
    }

    // MARK: Bottom row

    private var recentSessions: some View {
        Card("Recent sessions", trailing: AnyView(CardLink("See all") { onNavigate(.history) })) {
            LoadStateView(state: viewModel.recentSessions, emptyTitle: "No sessions yet", emptyMessage: "Tracked time appears here after it syncs.",
                          emptySymbol: "clock", isEmpty: { $0.isEmpty }, retry: { Task { await viewModel.loadRecentSessions() } }) { logs in
                let shown = Array(logs.prefix(4))
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, log in
                        ListItemRow(title: log.taskName,
                                    subtitle: "\(log.startedAt.formatted(.dateTime.weekday(.abbreviated))) · \(Format.time(log.startedAt))–\(Format.time(log.endedAt))",
                                    showsDivider: index < shown.count - 1) {
                            IconTile(symbol: "clock", tint: log.projectId.map(IdentityColor.color(for:)) ?? Palette.accent)
                        } trailing: {
                            Text(Format.duration(log.durationSec)).font(Typo.mono).monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    private var leaveBalance: some View {
        Card("Leave balance", trailing: AnyView(CardLink("Details") { onNavigate(.leaveBalance) })) {
            LoadStateView(state: viewModel.balance, retry: { Task { await viewModel.loadLeave() } }) { b in
                EqualColumns(count: 2, spacing: 10) {
                    MiniBalanceRing(title: "Paid", remaining: b.paidRemaining, total: b.paidAllocated, tint: Palette.accent)
                    MiniBalanceRing(title: "Comp-off", remaining: b.compOffRemaining, total: b.compOffBalance, tint: Palette.okFill)
                }
            }
        }
    }

    private var upcoming: some View {
        Card("Upcoming") {
            LoadStateView(state: viewModel.upcoming, emptyTitle: "Nothing coming up", emptySymbol: "calendar",
                          isEmpty: { $0.isEmpty }, retry: { Task { await viewModel.loadLeave() } }) { items in
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ListItemRow(title: Self.upcomingTitle(item), showsDivider: index < items.count - 1) {
                            DateBlock(date: item.date.date() ?? Date())
                        } trailing: {
                            UpcomingPill(kind: item.kind)
                        }
                    }
                }
            }
        }
    }

    private static func upcomingTitle(_ item: DashboardViewModel.UpcomingItem) -> String {
        guard let end = item.endDate, end != item.date else { return item.title }
        return "\(item.title) · \(Format.dateRange(item.date, end))"
    }
}

private struct UpcomingPill: View {
    let kind: DashboardViewModel.UpcomingItem.Kind
    var body: some View {
        switch kind {
        case .holiday: Pill(text: "Holiday", kind: .ok)
        case .leave(let status): LeaveStatusPill(status: status)
        }
    }
}

/// 48 pt balance ring + label (dashboard leave card).
struct MiniBalanceRing: View {
    let title: String
    let remaining: FlexibleDecimal?
    let total: FlexibleDecimal
    var tint: Color = Palette.accent

    var body: some View {
        HStack(spacing: 10) {
            ProgressRing(progress: total.doubleValue > 0 ? (remaining?.doubleValue ?? 0) / total.doubleValue : 0, lineWidth: 5, tint: tint) {
                Text(Format.days(remaining)).font(.system(size: 12, weight: .bold, design: .monospaced))
            }
            .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Typo.bodyEmphasis)
                Text("of \(Format.days(total))").font(Typo.small).foregroundStyle(Palette.textTertiary)
            }
        }
    }
}

/// KPI body used inside a KPI card.
struct StatTileBody: View {
    let value: String
    var suffix: String?
    var footnote: String?
    var progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            KPIText(value: value, suffix: suffix)
            if let progress { ProgressBar(value: progress, tint: Palette.blueFill).padding(.top, 4) }
            if let footnote { Text(footnote).font(Typo.caption).foregroundStyle(Palette.textTertiary).lineLimit(1) }
        }
    }
}

/// Invisible ⌘-shortcut trigger.
struct KeyboardShortcutButton: View {
    let key: KeyEquivalent
    let action: () -> Void
    var body: some View {
        Button("", action: action)
            .keyboardShortcut(key, modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}

/// Leave status → prototype pill (Approved ok · Pending wait · Rejected no · Cancelled gray).
struct LeaveStatusPill: View {
    let status: LeaveStatus?
    var body: some View {
        switch status {
        case .approved: Pill(text: "Approved", kind: .ok)
        case .pendingManager, .pendingAdmin: Pill(text: status?.displayName ?? "Pending", kind: .wait)
        case .rejected: Pill(text: "Rejected", kind: .no)
        case .cancelled: Pill(text: "Cancelled", kind: .gray)
        case .none: Pill(text: "Unknown", kind: .gray)
        }
    }
}
