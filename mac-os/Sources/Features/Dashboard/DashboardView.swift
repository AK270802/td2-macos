import SwiftUI
import Charts
import EffiLensKit

/// Dashboard — layout follows the prototype: greeting + action, KPI row,
/// active session + weekly chart, recent sessions + leave + upcoming.
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @State private var viewModel: DashboardViewModel
    let onNavigate: (Route) -> Void

    init(environment: AppEnvironment, onNavigate: @escaping (Route) -> Void) {
        _viewModel = State(initialValue: DashboardViewModel(environment: environment))
        self.onNavigate = onNavigate
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                header
                kpiRow
                HStack(alignment: .top, spacing: Space.l) {
                    ActiveSessionCard(onOpenTracker: { onNavigate(.tracker) })
                        .frame(maxWidth: 360)
                    weeklyChart
                }
                HStack(alignment: .top, spacing: Space.l) {
                    recentSessions
                    VStack(spacing: Space.l) {
                        leaveCard
                        upcomingCard
                    }
                    .frame(maxWidth: 360)
                }
            }
            .padding(Space.xl)
            .frame(maxWidth: 1240, alignment: .leading)
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                    .font(Typo.overline)
                    .tracking(0.6)
                    .foregroundStyle(Palette.textTertiary)
                Text("\(greeting), \(firstName).")
                    .font(Typo.display)
                    .foregroundStyle(Palette.textPrimary)
            }
            Spacer()
            Button {
                Task { try? await model.environment?.agent?.togglePlayPause() }
            } label: {
                Label(isRunning ? "Pause" : "Start Tracking", systemImage: isRunning ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.isAgentConnected)
            .help(model.isAgentConnected ? "Start or pause the timer (⌃⌥Space)" : "The tracking agent is not running.")
        }
    }

    private var isRunning: Bool { model.timerState?.state == .running }

    private var firstName: String {
        model.user?.displayName.split(separator: " ").first.map(String.init) ?? ""
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    // MARK: KPIs

    private var kpiRow: some View {
        Grid(horizontalSpacing: Space.l, verticalSpacing: Space.l) {
            GridRow {
                kpi(viewModel.today, label: "Today") { StatTile(label: "Today", value: Format.duration($0.workedSec), footnote: "\(Format.duration($0.meetingSec)) in meetings") }
                kpi(viewModel.week, label: "This week") { summary in
                    StatTile(
                        label: "This week",
                        value: Format.duration(summary.workedSec),
                        footnote: summary.requiredSec.map { "of \(Format.hours($0, fractionDigits: 0))h required" },
                        progress: summary.requiredSec.map { Double(summary.workedSec) / Double($0) }
                    )
                }
                kpi(viewModel.today, label: "Productivity") { StatTile(label: "Productivity", value: "\($0.productivePct)%", footnote: "\($0.utilisationPct)% utilisation today") }
                kpi(viewModel.balance, label: "Leave left") { balance in
                    StatTile(
                        label: "Leave left",
                        value: "\(Format.days(balance.paidRemaining)) days",
                        footnote: pendingFootnote,
                        footnoteTone: (viewModel.pendingLeaveCount ?? 0) > 0 ? Palette.warning : Palette.textSecondary
                    )
                }
            }
        }
    }

    private var pendingFootnote: String {
        switch viewModel.pendingLeaveCount {
        case .none: return "Paid leave remaining"
        case .some(0): return "No pending requests"
        case .some(1): return "1 request pending"
        case .some(let n): return "\(n) requests pending"
        }
    }

    @ViewBuilder
    private func kpi<V, C: View>(_ state: Loadable<V>, label: String, @ViewBuilder content: (V) -> C) -> some View {
        switch state {
        case .loaded(let value):
            content(value)
        case .failed:
            StatTile(label: label, value: "—", footnote: "Unavailable", footnoteTone: Palette.danger)
        case .idle, .loading:
            StatTile(label: label, value: "0h 00m").redacted(reason: .placeholder)
        }
    }

    // MARK: Weekly chart

    private var weeklyChart: some View {
        Card("Weekly activity", subtitle: "Active hours per day") {
            LoadStateView(
                state: viewModel.weeklyActivity,
                emptyTitle: "No activity this week",
                emptySymbol: "chart.bar",
                isEmpty: { $0.allSatisfy { $0.activeSec == 0 } },
                retry: { Task { await viewModel.loadWeeklyActivity() } }
            ) { days in
                Chart(days, id: \.date) { day in
                    BarMark(
                        x: .value("Day", day.date.date().map { $0.formatted(.dateTime.weekday(.abbreviated)) } ?? day.date.description),
                        y: .value("Hours", Double(day.activeSec) / 3600)
                    )
                    .foregroundStyle(day.date == CalendarDate(Date()) ? Palette.accent : Palette.accent.opacity(0.45))
                    .cornerRadius(4)
                    .annotation(position: .top, spacing: 4) {
                        if day.activeSec > 0 {
                            Text(Format.hours(day.activeSec)).font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(Palette.textSecondary)
                        }
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) { AxisGridLine().foregroundStyle(Palette.hairline); AxisValueLabel() } }
                .frame(height: 180)
                .accessibilityLabel("Active hours per day this week")
            }
        }
    }

    // MARK: Recent sessions

    private var recentSessions: some View {
        Card("Recent sessions", trailing: AnyView(Button("Time History") { onNavigate(.history) }.buttonStyle(.link))) {
            LoadStateView(
                state: viewModel.recentSessions,
                emptyTitle: "No sessions in the last 7 days",
                emptyMessage: "Start tracking a task to see it here.",
                emptySymbol: "clock",
                isEmpty: { $0.isEmpty },
                retry: { Task { await viewModel.loadRecentSessions() } }
            ) { logs in
                VStack(spacing: 0) {
                    ForEach(logs) { log in
                        HStack(spacing: Space.m) {
                            VStack(alignment: .leading, spacing: Space.xxs) {
                                Text(log.taskName.isEmpty ? "Untitled task" : log.taskName).font(Typo.bodyEmphasis).lineLimit(1)
                                Text("\(log.projectName) · \(log.startedAt.formatted(.dateTime.weekday(.abbreviated))) \(Format.time(log.startedAt))–\(Format.time(log.endedAt))")
                                    .font(Typo.caption).foregroundStyle(Palette.textSecondary).lineLimit(1)
                            }
                            Spacer()
                            if log.isManual { StatusPill(text: "Manual", tone: .info) }
                            Text(Format.duration(log.durationSec)).font(Typo.timerCompact).monospacedDigit()
                        }
                        .padding(.vertical, Space.s)
                        if log.id != logs.last?.id { Divider().overlay(Palette.hairline) }
                    }
                }
            }
        }
    }

    // MARK: Leave

    private var leaveCard: some View {
        Card("Leave balance", trailing: AnyView(Button("Overview") { onNavigate(.leaveOverview) }.buttonStyle(.link))) {
            LoadStateView(state: viewModel.balance, retry: { Task { await viewModel.loadLeave() } }) { balance in
                HStack(spacing: Space.xl) {
                    BalanceRing(title: "Paid", remaining: balance.paidRemaining, total: balance.paidAllocated)
                    BalanceRing(title: "Comp-off", remaining: balance.compOffRemaining, total: balance.compOffBalance)
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("Unpaid taken").font(Typo.caption).foregroundStyle(Palette.textSecondary)
                        Text("\(Format.days(balance.unpaidUsed)) d").font(Typo.heading).monospacedDigit()
                    }
                }
            }
        }
    }

    private var upcomingCard: some View {
        Card("Upcoming") {
            LoadStateView(
                state: viewModel.upcoming,
                emptyTitle: "Nothing scheduled",
                emptySymbol: "calendar",
                isEmpty: { $0.isEmpty },
                retry: { Task { await viewModel.loadLeave() } }
            ) { items in
                VStack(spacing: Space.s) {
                    ForEach(items) { item in
                        HStack(spacing: Space.m) {
                            DateBlock(date: item.date)
                            VStack(alignment: .leading, spacing: Space.xxs) {
                                Text(item.title).font(Typo.bodyEmphasis).lineLimit(1)
                                if let end = item.endDate, end != item.date {
                                    Text(Format.dateRange(item.date, end)).font(Typo.caption).foregroundStyle(Palette.textSecondary)
                                }
                            }
                            Spacer()
                            switch item.kind {
                            case .holiday: StatusPill(text: "Holiday", tone: .info)
                            case .leave(let status): LeaveStatusPill(status: status)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Small ring showing remaining / total days (server-computed values).
struct BalanceRing: View {
    let title: String
    let remaining: FlexibleDecimal?
    let total: FlexibleDecimal

    private var progress: Double {
        guard let remaining, total.doubleValue > 0 else { return 0 }
        return remaining.doubleValue / total.doubleValue
    }

    var body: some View {
        VStack(spacing: Space.xs) {
            ProgressRing(progress: progress, lineWidth: 5) {
                Text(Format.days(remaining)).font(.system(size: 13, weight: .semibold)).monospacedDigit()
            }
            .frame(width: 52, height: 52)
            Text(title).font(Typo.caption).foregroundStyle(Palette.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(Format.days(remaining)) of \(Format.days(total)) days remaining")
    }
}

struct DateBlock: View {
    let date: CalendarDate
    var body: some View {
        VStack(spacing: 0) {
            Text(date.date()?.formatted(.dateTime.month(.abbreviated)).uppercased() ?? "")
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.accent)
            Text("\(date.day)").font(.system(size: 15, weight: .semibold)).monospacedDigit()
        }
        .frame(width: 38, height: 38)
        .background(Palette.inset, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct LeaveStatusPill: View {
    let status: LeaveStatus?
    var body: some View {
        switch status {
        case .approved: StatusPill(text: "Approved", tone: .success)
        case .pendingManager, .pendingAdmin: StatusPill(text: status?.displayName ?? "Pending", tone: .warning)
        case .rejected: StatusPill(text: "Rejected", tone: .danger)
        case .cancelled: StatusPill(text: "Cancelled", tone: .neutral)
        case .none: StatusPill(text: "Unknown", tone: .neutral)
        }
    }
}
