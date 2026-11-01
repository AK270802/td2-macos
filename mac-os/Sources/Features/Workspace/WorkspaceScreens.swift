import AppKit
import SwiftUI
import Observation
import EffiLensKit

/// Period selector shared by Team, Reports and Activity.
enum ReportPeriod: String, CaseIterable, Identifiable {
    case today = "Today", week = "This Week", month = "This Month", last30 = "Last 30 Days"
    var id: String { rawValue }

    var range: DateRange {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .today: return .today()
        case .week: return .thisWeek()
        case .month:
            let start = cal.dateInterval(of: .month, for: now)?.start ?? now
            return DateRange(from: CalendarDate(start), to: CalendarDate(now))
        case .last30:
            let start = cal.date(byAdding: .day, value: -29, to: now) ?? now
            return DateRange(from: CalendarDate(start), to: CalendarDate(now))
        }
    }
}

struct PeriodPicker: View {
    @Binding var period: ReportPeriod
    var options: [ReportPeriod] = ReportPeriod.allCases
    var body: some View {
        EffiSegmented(selection: $period, options: options.map { ($0, $0.rawValue) })
    }
}

extension Result where Failure == Error {
    /// Async catching initialiser (Swift's `Result(catching:)` is synchronous).
    init(awaiting body: () async throws -> Success) async {
        do { self = .success(try await body()) } catch { self = .failure(error) }
    }
}

// MARK: - Approvals (prototype V.approvals; manager+)

@MainActor
@Observable
final class ApprovalsViewModel {
    private(set) var pending: Loadable<[LeaveApplication]> = .idle
    var actionError: AppError?
    var actionMessage: String?
    private(set) var working: Set<UUID> = []
    private let leave: LeaveService
    private let me: UUID?
    let role: UserRole

    init(environment: AppEnvironment, me: UUID?, role: UserRole) {
        leave = environment.leave
        self.me = me
        self.role = role
    }

    func load() async {
        if pending.value == nil { pending = .loading }
        do {
            // Server scopes the list to the reviewer's team / tenant.
            var items = try await leave.applications(status: .pendingManager, pageSize: 200).items
            if role.atLeast(.admin) {
                items += try await leave.applications(status: .pendingAdmin, pageSize: 200).items
            }
            pending = .loaded(items.filter { $0.userId != me }.sorted { $0.startDate < $1.startDate })
        } catch { pending = .failed(DashboardViewModel.map(error)) }
    }

    func mode(for application: LeaveApplication) -> LeaveDetailView.Mode {
        LeaveRules.approverLevel(application, role: role) == .admin ? .adminReview : .managerReview
    }

    func approve(_ a: LeaveApplication) async {
        working.insert(a.id)
        defer { working.remove(a.id) }
        do {
            if mode(for: a) == .adminReview { _ = try await leave.adminApprove(a.id) } else { _ = try await leave.managerApprove(a) }
            actionMessage = "\(a.userDisplayName ?? "Request") approved."
            await load()
        } catch { actionError = DashboardViewModel.map(error) }
    }

    func reject(_ a: LeaveApplication, reason: String) async {
        working.insert(a.id)
        defer { working.remove(a.id) }
        do {
            if mode(for: a) == .adminReview { _ = try await leave.adminReject(a.id, reason: reason) } else { _ = try await leave.managerReject(a.id, reason: reason) }
            actionMessage = "\(a.userDisplayName ?? "Request") rejected."
            await load()
        } catch { actionError = DashboardViewModel.map(error) }
    }
}

struct ApprovalsView: View {
    @Environment(Navigator.self) private var navigator
    @State private var viewModel: ApprovalsViewModel
    @State private var rejecting: LeaveApplication?
    @State private var rejectReason = ""

    init(environment: AppEnvironment, me: UUID?, role: UserRole) {
        _viewModel = State(initialValue: ApprovalsViewModel(environment: environment, me: me, role: role))
    }

    var body: some View {
        Page {
            Card(tint: Palette.accent) {
                HStack {
                    Text("Manager view — visible only to approvers.").font(Typo.body).foregroundStyle(Palette.textSecondary)
                    Spacer()
                    if let message = viewModel.actionMessage { Text(message).font(Typo.caption).foregroundStyle(Palette.success) }
                }
            }
            LoadStateView(state: viewModel.pending, emptyTitle: "All caught up", emptyMessage: "No leave requests are waiting for you.",
                          emptySymbol: "checkmark.seal", isEmpty: { $0.isEmpty }, retry: { Task { await viewModel.load() } }) { items in
                VStack(spacing: 10) {
                    ForEach(items) { a in approvalCard(a) }
                }
            }
        }
        .task { await viewModel.load() }
        .sheet(item: $rejecting) { a in rejectSheet(a) }
        .alert("Action failed", isPresented: Binding(get: { viewModel.actionError != nil }, set: { if !$0 { viewModel.actionError = nil } }),
               presenting: viewModel.actionError) { _ in Button("OK", role: .cancel) {} } message: { Text($0.userMessage) }
    }

    private func approvalCard(_ a: LeaveApplication) -> some View {
        let name = a.userDisplayName ?? a.userEmail ?? "Employee"
        return Card {
            HStack(spacing: 10) {
                InitialsAvatar(initials: name.initials, color: IdentityColor.color(for: a.userId))
                VStack(alignment: .leading, spacing: 2) {
                    (Text(name).font(Typo.bodyEmphasis) + Text(" · \(a.kind?.displayName ?? "Leave") · \(Format.days(a.durationDays)) day\(a.durationDays.doubleValue == 1 ? "" : "s")").font(Typo.body))
                    Text([Format.dateRange(a.startDate, a.endDate), a.reason.map { "“\($0)”" }, a.statusValue?.displayName].compactMap { $0 }.joined(separator: " · "))
                        .font(Typo.caption).foregroundStyle(Palette.textTertiary).lineLimit(1)
                }
                Spacer()
                if viewModel.working.contains(a.id) {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Details") {
                        navigator.leaveDetail = LeaveDetailContext(application: a, mode: viewModel.mode(for: a), back: .approvals)
                    }
                    .buttonStyle(.effi)
                    Button("Reject") { rejectReason = ""; rejecting = a }.buttonStyle(.effiDanger)
                    Button("Approve") { Task { await viewModel.approve(a) } }.buttonStyle(.effiPrimary)
                }
            }
        }
    }

    private func rejectSheet(_ a: LeaveApplication) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Reject \(a.userDisplayName ?? "request")?").font(.system(size: 13.5, weight: .semibold))
            Text("\(Format.dateRange(a.startDate, a.endDate)) · the reason is sent to the employee.").font(Typo.caption).foregroundStyle(Palette.textSecondary).padding(.top, 4)
            FieldLabel("Reason")
            EffiTextArea(placeholder: "Reason for rejection", text: $rejectReason)
            HStack {
                Spacer()
                Button("Cancel") { rejecting = nil }.buttonStyle(.effi).keyboardShortcut(.cancelAction)
                Button("Reject") {
                    let reason = rejectReason.trimmingCharacters(in: .whitespacesAndNewlines)
                    rejecting = nil
                    Task { await viewModel.reject(a, reason: reason) }
                }
                .buttonStyle(.effiDanger)
                .disabled(rejectReason.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 16)
        }
        .padding(20)
        .frame(width: 420)
        .background(Palette.surfaceRaised)
    }
}

// MARK: - Team (prototype V.team; GET /dashboard/team, manager+)

/// Presence derived from the agent's last check-in (`last_device_seen`).
/// Agents check in on every sync, so this is "recently active", not a live
/// idle indicator — the label always says when the member was last seen.
struct Presence: Equatable {
    let lastSeen: Date?

    var isActive: Bool { lastSeen.map { Date().timeIntervalSince($0) < 15 * 60 } ?? false }

    var label: String {
        guard let lastSeen else { return "Never seen" }
        return isActive ? "Active · \(Format.relative(lastSeen))" : "Last seen \(Format.relative(lastSeen))"
    }

    var kind: Pill.Kind { isActive ? .ok : (lastSeen == nil ? .gray : .wait) }
}

/// `activity_level` (very_high … very_low) → label + pill tint.
enum ActivityLevelLabel {
    static func text(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized + " activity"
    }
    static func kind(_ raw: String) -> Pill.Kind {
        switch raw {
        case "very_high", "high": return .ok
        case "medium": return .blue
        case "low": return .wait
        default: return .gray
        }
    }
}

struct TeamView: View {
    @Environment(Navigator.self) private var navigator
    @State private var period: ReportPeriod = .today
    @State private var data: Loadable<TeamDashboardResponse> = .idle
    @State private var presence: [UUID: Presence] = [:]
    private let environment: AppEnvironment

    init(environment: AppEnvironment) { self.environment = environment }

    private struct Member: Identifiable {
        let item: UserTimeItem
        let tracking: Bool
        var id: UUID { item.userId }
    }

    var body: some View {
        Page {
            HStack {
                PeriodPicker(period: $period)
                Spacer()
                Text("Presence = last agent check-in").font(Typo.caption).foregroundStyle(Palette.textTertiary)
            }
            LoadStateView(state: data, retry: { Task { await load() } }) { team in
                let members = team.mostHoursUsers.map { Member(item: $0, tracking: true) } + team.usersNotTracking.map { Member(item: $0, tracking: false) }
                EqualColumns(count: 3) {
                    StatTile(label: "Active now", value: "\(members.filter { presence[$0.id]?.isActive == true }.count)", suffix: "/ \(members.count)")
                    StatTile(label: "Not tracking", value: "\(team.usersNotTracking.count)")
                    StatTile(label: "Team hours", value: Format.duration(team.summary.workedSec))
                }
                if members.isEmpty {
                    Card { EmptyStateView(title: "No team members", message: "Members assigned to you appear here.", symbol: "person.2") }
                } else {
                    EqualColumns(count: 3) {
                        ForEach(members) { m in memberCard(m) }
                    }
                }
            }
        }
        .task(id: period) { await load() }
    }

    private func memberCard(_ m: Member) -> some View {
        Button {
            navigator.member = MemberContext(member: m.item, period: period)
        } label: {
            Card {
                HStack(spacing: 10) {
                    InitialsAvatar(initials: m.item.displayName.initials, size: 42, color: IdentityColor.color(for: m.item.userId))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(m.item.displayName).font(Typo.bodyEmphasis).lineLimit(1)
                        Text(m.item.email).font(Typo.caption).foregroundStyle(Palette.textTertiary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                HStack {
                    if let p = presence[m.id] {
                        Pill(text: "● \(p.label)", kind: p.kind)
                    } else {
                        Pill(text: m.tracking ? "● Tracked" : "● No activity", kind: m.tracking ? .ok : .gray)
                    }
                    Spacer()
                    Text(Format.duration(m.item.totalSec)).font(Typo.mono)
                }
                .padding(.top, 4)
                Pill(text: ActivityLevelLabel.text(m.item.activityLevel), kind: ActivityLevelLabel.kind(m.item.activityLevel))
            }
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        if data.value == nil { data = .loading }
        do {
            let team = try await environment.insights.teamDashboard(range: period.range)
            data = .loaded(team)
            await loadPresence(ids: (team.mostHoursUsers + team.usersNotTracking).map(\.userId))
        } catch { data = .failed(DashboardViewModel.map(error)) }
    }

    /// One `GET /users/{id}` per member (manager/admin), at most 6 in flight.
    private func loadPresence(ids: [UUID]) async {
        let profile = environment.profile
        var result: [UUID: Presence] = [:]
        for chunk in stride(from: 0, to: ids.count, by: 6).map({ Array(ids[$0..<min($0 + 6, ids.count)]) }) {
            await withTaskGroup(of: (UUID, UserDetail?).self) { group in
                for id in chunk {
                    group.addTask {
                        let detail = try? await profile.user(id)
                        return (id, detail)
                    }
                }
                for await (id, detail) in group {
                    if let detail { result[id] = Presence(lastSeen: detail.lastDeviceSeen) }
                }
            }
        }
        presence = result
    }
}

/// Team member page (prototype V.member).
struct MemberDetailView: View {
    let member: UserTimeItem
    let period: ReportPeriod
    let environment: AppEnvironment
    @Environment(Navigator.self) private var navigator
    @State private var data: Loadable<IndividualDashboardResponse> = .idle
    @State private var balance: LeaveBalance?
    @State private var detail: UserDetail?

    var body: some View {
        Page {
            HStack { Button("‹ Team") { navigator.member = nil }.buttonStyle(.effi) }
            Card {
                HStack(spacing: 18) {
                    InitialsAvatar(initials: member.displayName.initials, size: 70, color: IdentityColor.color(for: member.userId))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.displayName).font(Typo.pageTitle)
                        Text(member.email).font(Typo.body).foregroundStyle(Palette.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        if let detail {
                            let p = Presence(lastSeen: detail.lastDeviceSeen)
                            Pill(text: "● \(p.label)", kind: p.kind)
                        }
                        Pill(text: ActivityLevelLabel.text(member.activityLevel), kind: ActivityLevelLabel.kind(member.activityLevel))
                    }
                }
            }
            LoadStateView(state: data, retry: { Task { await load() } }) { d in
                EqualColumns(count: 3) {
                    StatTile(label: period.rawValue, value: Format.duration(d.summary.workedSec))
                    StatTile(label: "Productivity", value: "\(d.summary.productivePct)", suffix: "%")
                    StatTile(label: "Leave left", value: balance.map { Format.days($0.paidRemaining) } ?? "—", suffix: balance == nil ? nil : "days")
                }
                if !d.topProjects.isEmpty {
                    Card("Projects") {
                        VStack(spacing: 0) {
                            ForEach(Array(d.topProjects.enumerated()), id: \.element.id) { index, p in
                                ListItemRow(title: p.projectName, showsDivider: index < d.topProjects.count - 1) {
                                    IconTile(symbol: "folder", tint: IdentityColor.color(for: p.projectId))
                                } trailing: {
                                    Text(Format.duration(p.totalSec)).font(Typo.mono)
                                }
                            }
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        data = .loading
        do { data = .loaded(try await environment.insights.individualDashboard(range: period.range, userId: member.userId)) }
        catch { data = .failed(DashboardViewModel.map(error)) }
        balance = try? await environment.leave.balance(userId: member.userId)
        detail = try? await environment.profile.user(member.userId)
    }
}

// MARK: - Reports (prototype V.reports)

struct ReportsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case productivity = "Productivity", time = "Time", attendance = "Attendance", leave = "Leave"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @State private var tab: Tab = .productivity
    @State private var period: ReportPeriod = .week
    private let environment: AppEnvironment

    init(environment: AppEnvironment) { self.environment = environment }

    var body: some View {
        Page {
            HStack {
                EffiSegmented(selection: $tab, options: Tab.allCases.map { ($0, $0.rawValue) })
                Spacer()
                PeriodPicker(period: $period, options: [.week, .month, .last30])
                if let portal = environment.configuration.portalOrigin {
                    Button("Export in Portal") { NSWorkspace.shared.open(portal) }
                        .buttonStyle(.effi)
                        .help("PDF/CSV exports are generated by the web portal.")
                }
            }
            switch tab {
            case .productivity: ProductivityReport(environment: environment, period: period)
            case .time: TimeReport(environment: environment, period: period)
            case .attendance: AttendanceReport(environment: environment, period: period)
            case .leave: LeaveReport(environment: environment, period: period)
            }
        }
    }
}

private struct ProductivityReport: View {
    let environment: AppEnvironment
    let period: ReportPeriod
    @State private var scores: Loadable<ProductivityScoreResponse> = .idle
    @State private var dashboard: IndividualDashboardResponse?
    @State private var apps: AppUsageResponse?

    var body: some View {
        LoadStateView(state: scores, emptyTitle: "No activity in this period", emptySymbol: "chart.bar",
                      isEmpty: { $0.days.isEmpty }, retry: { Task { await load() } }) { r in
            EqualColumns(count: 4) {
                StatTile(label: "Focus score", value: "\(Int(r.avgScore.rounded()))", suffix: "%")
                StatTile(label: "Active time", value: dashboard.map { Format.duration($0.summary.workedSec - $0.summary.idleSec) } ?? "—")
                StatTile(label: "Idle time", value: dashboard.map { Format.duration($0.summary.idleSec) } ?? "—")
                StatTile(label: "Top app", value: apps?.items.first?.appName ?? "—")
            }
            EqualColumns(count: 2) {
                Card("Daily productivity") {
                    BarsChart(bars: r.days.suffix(14).map { d in
                        BarsChart.Bar(label: d.date.date()?.formatted(.dateTime.weekday(.narrow)) ?? "", value: d.score,
                                      valueText: d.totalTrackedSec > 0 ? "\(Int(d.score.rounded()))" : "")
                    }, maxValue: 100, gradient: [Color(hex: 0xC3A6FF), Palette.violetFill])
                }
                Card("App usage") {
                    if let apps, !apps.items.isEmpty {
                        VStack(spacing: 9) {
                            ForEach(Array(apps.items.prefix(5).enumerated()), id: \.offset) { index, a in
                                VStack(spacing: 5) {
                                    HStack { Text(a.appName); Spacer(); Text("\(Int(a.percentage.rounded()))%").font(Typo.mono) }
                                    ProgressBar(value: a.percentage / 100, tint: Palette.chartSeries[index % Palette.chartSeries.count])
                                }
                            }
                        }
                    } else {
                        EmptyStateView(title: "No app usage", symbol: "macwindow")
                    }
                }
            }
        }
        .task(id: period) { await load() }
    }

    private func load() async {
        scores = .loading
        let range = period.range
        do { scores = .loaded(try await environment.insights.productivity(range: range)) } catch { scores = .failed(DashboardViewModel.map(error)) }
        dashboard = try? await environment.insights.individualDashboard(range: range)
        apps = try? await environment.insights.appUsage(range: range, pageSize: 5)
    }
}

private struct TimeReport: View {
    let environment: AppEnvironment
    let period: ReportPeriod
    @State private var projects: Loadable<ProjectTimeSummaryResponse> = .idle

    private struct Row: Identifiable {
        let id: Int
        let item: ProjectTimeSummaryItem
        let share: Double
    }

    var body: some View {
        Card(padding: 6) {
            LoadStateView(state: projects, emptyTitle: "No time logged", emptySymbol: "clock",
                          isEmpty: { $0.items.isEmpty }, retry: { Task { await load() } }) { p in
                let rows = p.items.enumerated().map { Row(id: $0.offset, item: $0.element, share: p.totalDurationSec > 0 ? Double($0.element.totalDurationSec) / Double(p.totalDurationSec) : 0) }
                EffiTable<Row>(rows: rows, columns: [
                    .init("Project") { r in Text(r.item.projectName ?? "Unassigned").font(Typo.bodyEmphasis) },
                    .init("Tasks", width: 70) { r in Text(r.item.taskCount.map { String($0) } ?? "—").font(Typo.mono) },
                    .init("Sessions", width: 80) { r in Text(r.item.logCount.map { String($0) } ?? "—").font(Typo.mono) },
                    .init(period.rawValue, width: 110) { r in Text(Format.duration(r.item.totalDurationSec)).font(Typo.mono) },
                    .init("Share", width: 240) { r in ProgressBar(value: r.share, tint: r.item.projectId.map(IdentityColor.color(for:)) ?? Palette.accent) },
                ])
            }
        }
        .task(id: period) { await load() }
    }

    private func load() async {
        projects = .loading
        do { projects = .loaded(try await environment.work.projectSummary(range: period.range)) } catch { projects = .failed(DashboardViewModel.map(error)) }
    }
}

private struct AttendanceReport: View {
    let environment: AppEnvironment
    let period: ReportPeriod
    @State private var data: Loadable<UtilisationResponse> = .idle

    var body: some View {
        LoadStateView(state: data, emptyTitle: "No attendance data", emptySymbol: "calendar",
                      isEmpty: { $0.days.isEmpty }, retry: { Task { await load() } }) { r in
            let worked = r.days.filter { $0.activeSec > 0 }
            EqualColumns(count: 4) {
                StatTile(label: "Days worked", value: "\(worked.count)", suffix: "/ \(r.days.count)")
                StatTile(label: "Avg. utilisation", value: "\(Int(r.avgUtilisationPct.rounded()))", suffix: "%")
                StatTile(label: "Avg. active", value: worked.isEmpty ? "—" : Format.duration(worked.reduce(0) { $0 + $1.activeSec } / worked.count))
                StatTile(label: "Breaks", value: Format.duration(r.days.reduce(0) { $0 + $1.breakSec }))
            }
            Card("Activity heat-map") {
                let maxActive = max(r.days.map(\.activeSec).max() ?? 1, 1)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: min(max(r.days.count, 7), 31)), spacing: 4) {
                    ForEach(r.days, id: \.date) { d in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Palette.accent.opacity(d.activeSec == 0 ? 0.06 : 0.25 + 0.7 * Double(d.activeSec) / Double(maxActive)))
                            .aspectRatio(1, contentMode: .fit)
                            .help("\(d.date.description): \(Format.duration(d.activeSec)) active")
                    }
                }
            }
        }
        .task(id: period) { await load() }
    }

    private func load() async {
        data = .loading
        do { data = .loaded(try await environment.insights.utilisation(range: period.range)) } catch { data = .failed(DashboardViewModel.map(error)) }
    }
}

private struct LeaveReport: View {
    let environment: AppEnvironment
    let period: ReportPeriod
    @Environment(Navigator.self) private var navigator
    @State private var data: Loadable<[LeaveApplication]> = .idle

    var body: some View {
        LoadStateView(state: data, emptyTitle: "No leave in this period", emptySymbol: "calendar.badge.clock",
                      isEmpty: { $0.isEmpty }, retry: { Task { await load() } }) { items in
            let approved = items.filter { $0.statusValue == .approved }
            EqualColumns(count: 3) {
                StatTile(label: "Requests", value: "\(items.count)")
                StatTile(label: "Approved days", value: Format.days(FlexibleDecimal(approved.reduce(Decimal(0)) { $0 + $1.durationDays.value })))
                StatTile(label: "Pending", value: "\(items.filter { $0.statusValue?.isPending == true }.count)")
            }
            Card(padding: 6) {
                LeaveApplicationTable(items: items, showEmployee: true) { a in
                    navigator.leaveDetail = LeaveDetailContext(application: a, mode: .own, back: .reports)
                }
            }
        }
        .task(id: period) { await load() }
    }

    private func load() async {
        data = .loading
        do {
            let r = period.range
            data = .loaded(try await environment.leave.applications(startFrom: r.from, startTo: r.to, pageSize: 200).items)
        } catch { data = .failed(DashboardViewModel.map(error)) }
    }
}

// MARK: - Notifications (prototype V.notifications)

struct NotificationsView: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator
    @State private var data: Loadable<NotificationListResponse> = .idle
    @State private var error: AppError?
    private let service: NotificationService

    init(environment: AppEnvironment) { service = environment.notifications }

    var body: some View {
        Page {
            HStack {
                Text("\(data.value?.unreadCount ?? model.unreadNotifications) unread").font(Typo.body).foregroundStyle(Palette.textSecondary)
                Spacer()
                Button("Mark all read") { Task { await markAll() } }.buttonStyle(.effi).disabled((data.value?.unreadCount ?? 0) == 0)
                Button("Preferences") { navigator.go(.settings) }.buttonStyle(.effi)
            }
            Card(padding: 14) {
                LoadStateView(state: data, emptyTitle: "No notifications", emptySymbol: "bell.slash",
                              isEmpty: { $0.items.isEmpty }, retry: { Task { await load() } }) { list in
                    VStack(spacing: 0) {
                        ForEach(Array(list.items.enumerated()), id: \.element.id) { index, item in
                            Button {
                                if !item.isRead { Task { await markRead(item) } }
                            } label: {
                                ListItemRow(title: item.title, subtitle: item.message, bold: !item.isRead, showsDivider: index < list.items.count - 1) {
                                    IconTile(symbol: "bell", tint: tint(for: item))
                                } trailing: {
                                    Text(Format.relative(item.createdAt)).font(Typo.small).foregroundStyle(Palette.textTertiary)
                                    if !item.isRead { Circle().fill(Palette.blueFill).frame(width: 8, height: 8) }
                                }
                                .opacity(item.isRead ? 0.85 : 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .task { await load() }
        .alert("Couldn't update notifications", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } }),
               presenting: error) { _ in Button("OK", role: .cancel) {} } message: { Text($0.userMessage) }
    }

    private func tint(for item: NotificationItem) -> Color {
        let t = item.type.lowercased()
        if t.contains("approved") { return Palette.okFill }
        if t.contains("reject") { return Palette.redFill }
        if t.contains("leave") { return Palette.violetFill }
        return Palette.accent
    }

    private func load() async {
        if data.value == nil { data = .loading }
        do { data = .loaded(try await service.list(limit: 100)) } catch { data = .failed(DashboardViewModel.map(error)) }
        await model.refreshUnreadCount()
    }

    private func markRead(_ item: NotificationItem) async {
        do { _ = try await service.markRead(item.id); await load() } catch { self.error = DashboardViewModel.map(error) }
    }

    private func markAll() async {
        do { _ = try await service.markAllRead(); await load() } catch { self.error = DashboardViewModel.map(error) }
    }
}

// MARK: - Activity timeline (prototype V.activity; GET /analytics/timeline)

/// The user's synced activity events (app, website domain, idle, meetings) —
/// the same stream the portal's Activity page shows — plus how many events are
/// still queued on this Mac.
struct ActivityView: View {
    @Environment(AppModel.self) private var model
    @State private var period: ReportPeriod = .today
    @State private var data: Loadable<TimelineResponse> = .idle
    private let insights: InsightsService

    init(environment: AppEnvironment) { insights = environment.insights }

    var body: some View {
        Page {
            HStack {
                PeriodPicker(period: $period, options: [.today, .week])
                Spacer()
                if let pending = model.syncStatus?.pendingEvents, pending > 0 {
                    Pill(text: "\(pending) event\(pending == 1 ? "" : "s") waiting to sync from this Mac", kind: .wait)
                }
            }
            LoadStateView(state: data, emptyTitle: "No activity yet", emptyMessage: "Events appear here after the agent syncs (every few minutes while you track).",
                          emptySymbol: "list.bullet.rectangle", isEmpty: { $0.events.isEmpty }, retry: { Task { await load() } }) { t in
                EqualColumns(count: 3) {
                    StatTile(label: "Active", value: Format.duration(t.totalActiveSec))
                    StatTile(label: "Idle", value: Format.duration(t.totalIdleSec))
                    StatTile(label: "Events", value: "\(t.totalEvents)")
                }
                Card {
                    let events = t.events.sorted { $0.ts > $1.ts }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(events.enumerated()), id: \.element.id) { index, e in
                            TimelineItem(tone: Self.tone(e), isLast: index == events.count - 1) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(Format.time(e.ts)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.textTertiary)
                                        Text(Self.title(e)).font(Typo.body).lineLimit(1)
                                        if let title = e.windowTitle, !title.isEmpty, e.eventType != "idle" {
                                            Text(title).font(Typo.caption).foregroundStyle(Palette.textTertiary).lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    if let category = e.category { Pill(text: Self.categoryLabel(category), kind: Self.categoryKind(category)) }
                                    Text(Format.duration(e.durationSec)).font(Typo.mono).frame(width: 70, alignment: .trailing)
                                }
                            }
                        }
                    }
                }
                if t.totalEvents > t.events.count {
                    Text("Showing the latest \(t.events.count) of \(t.totalEvents) events.").font(Typo.caption).foregroundStyle(Palette.textTertiary)
                }
            }
        }
        .task(id: period) { await load() }
    }

    private static func title(_ e: TimelineEvent) -> String {
        switch e.eventType {
        case "idle": return "Idle"
        case "meeting": return "Meeting\(e.appName.map { " · \($0)" } ?? "")"
        case "browser": return e.domain ?? e.appName ?? "Browser"
        default: return e.appName ?? e.domain ?? e.eventType.capitalized
        }
    }

    private static func tone(_ e: TimelineEvent) -> TimelineTone {
        if e.eventType == "idle" { return .no }
        return e.category == "productive" ? .ok : .accent
    }

    private static func categoryLabel(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private static func categoryKind(_ raw: String) -> Pill.Kind {
        switch raw {
        case "productive": return .ok
        case "non_productive", "unproductive": return .no
        default: return .gray
        }
    }

    private func load() async {
        if data.value == nil { data = .loading }
        do { data = .loaded(try await insights.timeline(range: period.range, pageSize: 200)) }
        catch { data = .failed(DashboardViewModel.map(error)) }
    }
}
