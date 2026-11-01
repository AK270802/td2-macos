import SwiftUI
import Charts
import Observation
import EffiLensKit

/// Today / this week / this month selector shared by Team, Reports, Activity.
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
    var body: some View {
        Picker("Period", selection: $period) {
            ForEach(ReportPeriod.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 440)
        .labelsHidden()
    }
}

// MARK: - Approvals (manager+)

@MainActor
@Observable
final class ApprovalsViewModel {
    private(set) var pending: Loadable<[LeaveApplication]> = .idle
    var selection: Set<UUID> = []
    var actionError: AppError?
    var actionMessage: String?
    private(set) var working = false
    private let leave: LeaveService
    private let me: UUID?
    let role: UserRole

    init(environment: AppEnvironment, me: UUID?, role: UserRole) {
        leave = environment.leave
        self.me = me
        self.role = role
    }

    func load() async {
        pending = .loading
        do {
            // Server scopes the list to the reviewer's team / tenant.
            var items = try await leave.applications(status: .pendingManager, pageSize: 200).items
            if role.atLeast(.admin) {
                items += try await leave.applications(status: .pendingAdmin, pageSize: 200).items
            }
            pending = .loaded(items.filter { $0.userId != me }.sorted { $0.startDate < $1.startDate })
            selection = selection.intersection(Set(items.map(\.id)))
        } catch { pending = .failed(DashboardViewModel.map(error)) }
    }

    func mode(for application: LeaveApplication) -> LeaveDetailView.Mode {
        application.statusValue == .pendingAdmin && role.atLeast(.admin) ? .adminReview : .managerReview
    }

    func bulkApprove() async {
        working = true
        defer { working = false }
        do {
            let result = try await leave.bulkApprove(Array(selection))
            actionMessage = "Approved \(result.succeededCount) of \(result.total)." + (result.failedCount > 0 ? " \(result.failedCount) could not be approved." : "")
            selection = []
            await load()
        } catch { actionError = DashboardViewModel.map(error) }
    }

    func bulkReject(reason: String) async {
        working = true
        defer { working = false }
        do {
            let result = try await leave.bulkReject(Array(selection), reason: reason)
            actionMessage = "Rejected \(result.succeededCount) of \(result.total)."
            selection = []
            await load()
        } catch { actionError = DashboardViewModel.map(error) }
    }
}

struct ApprovalsView: View {
    @State private var viewModel: ApprovalsViewModel
    @State private var detail: LeaveApplication?
    @State private var showBulkReject = false
    @State private var bulkReason = ""
    private let environment: AppEnvironment

    init(environment: AppEnvironment, me: UUID?, role: UserRole) {
        self.environment = environment
        _viewModel = State(initialValue: ApprovalsViewModel(environment: environment, me: me, role: role))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Text("Leave requests waiting for your decision").font(Typo.heading)
                Spacer()
                if let message = viewModel.actionMessage { Text(message).font(Typo.caption).foregroundStyle(Palette.success) }
                Button("Reject Selected…") { showBulkReject = true }
                    .disabled(viewModel.selection.isEmpty || viewModel.working)
                Button("Approve Selected") { Task { await viewModel.bulkApprove() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.selection.isEmpty || viewModel.working)
            }
            .padding([.horizontal, .top], Space.xl)

            LoadStateView(state: viewModel.pending, emptyTitle: "All caught up", emptyMessage: "No leave requests are waiting for you.",
                          emptySymbol: "checkmark.seal", isEmpty: { $0.isEmpty }, retry: { Task { await viewModel.load() } }) { items in
                Table(items, selection: $viewModel.selection) {
                    TableColumn("Employee") { a in Text(a.userDisplayName ?? a.userEmail ?? "—").font(Typo.bodyEmphasis) }
                    TableColumn("Dates") { a in Text(Format.dateRange(a.startDate, a.endDate)) }
                    TableColumn("Days") { a in Text(Format.days(a.durationDays)).monospacedDigit() }.width(50)
                    TableColumn("Stage") { a in LeaveStatusPill(status: a.statusValue) }.width(150)
                    TableColumn("Reason") { a in Text(a.reason ?? "—").lineLimit(1).foregroundStyle(Palette.textSecondary) }
                    TableColumn("") { a in Button("Review") { detail = a }.controlSize(.small) }.width(80)
                }
            }
        }
        .task { await viewModel.load() }
        .sheet(item: $detail) { application in
            LeaveDetailView(application: application, environment: environment, mode: viewModel.mode(for: application)) {
                Task { await viewModel.load() }
            }
        }
        .sheet(isPresented: $showBulkReject) {
            VStack(alignment: .leading, spacing: Space.l) {
                Text("Reject \(viewModel.selection.count) request(s)").font(Typo.title)
                TextField("Reason (sent to the employees)", text: $bulkReason, axis: .vertical).lineLimit(3...6).textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { showBulkReject = false }
                    Button("Reject", role: .destructive) {
                        let reason = bulkReason.trimmingCharacters(in: .whitespacesAndNewlines)
                        showBulkReject = false
                        bulkReason = ""
                        Task { await viewModel.bulkReject(reason: reason) }
                    }
                    .disabled(bulkReason.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(Space.xl)
            .frame(width: 440)
        }
        .alert("Action failed", isPresented: Binding(get: { viewModel.actionError != nil }, set: { if !$0 { viewModel.actionError = nil } }),
               presenting: viewModel.actionError) { _ in Button("OK", role: .cancel) {} } message: { Text($0.userMessage) }
    }
}

// MARK: - Team (manager+, GET /dashboard/team)

struct TeamView: View {
    @State private var period: ReportPeriod = .today
    @State private var data: Loadable<TeamDashboardResponse> = .idle
    @State private var member: UserTimeItem?
    private let environment: AppEnvironment

    init(environment: AppEnvironment) { self.environment = environment }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                PeriodPicker(period: $period)
                Text("Live presence isn't available from the server yet; figures reflect synced activity.")
                    .font(Typo.caption).foregroundStyle(Palette.textSecondary)
                LoadStateView(state: data, retry: { Task { await load() } }) { team in
                    HStack(spacing: Space.l) {
                        StatTile(label: "Active members", value: "\(team.summary.activeUsers)")
                        StatTile(label: "Worked", value: Format.duration(team.summary.workedSec))
                        StatTile(label: "Productive", value: "\(team.summary.productivePct)%")
                        StatTile(label: "Utilisation", value: "\(team.summary.utilisationPct)%")
                    }
                    Card("Members by hours") {
                        if team.mostHoursUsers.isEmpty {
                            Text("No tracked time in this period.").foregroundStyle(Palette.textSecondary)
                        } else {
                            memberTable(team.mostHoursUsers)
                        }
                    }
                    Card("Not tracking", subtitle: "No synced activity in this period") {
                        if team.usersNotTracking.isEmpty {
                            Text("Everyone has tracked time.").foregroundStyle(Palette.textSecondary)
                        } else {
                            ForEach(team.usersNotTracking) { u in
                                HStack {
                                    InitialsAvatar(initials: String(u.displayName.prefix(1)))
                                    Text(u.displayName)
                                    Text(u.email).foregroundStyle(Palette.textSecondary).font(Typo.caption)
                                    Spacer()
                                }
                            }
                        }
                    }
                }
            }
            .padding(Space.xl)
            .frame(maxWidth: 1200, alignment: .leading)
        }
        .task(id: period) { await load() }
        .sheet(item: $member) { m in MemberDetailView(member: m, period: period, environment: environment) }
    }

    private func memberTable(_ users: [UserTimeItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(users) { u in
                Button { member = u } label: {
                    HStack(spacing: Space.m) {
                        InitialsAvatar(initials: String(u.displayName.prefix(1)))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(u.displayName).font(Typo.bodyEmphasis)
                            Text(u.email).font(Typo.caption).foregroundStyle(Palette.textSecondary)
                        }
                        Spacer()
                        Text(Format.duration(u.totalSec)).monospacedDigit().frame(width: 80, alignment: .trailing)
                        Text("\(u.productivePct)% productive").font(Typo.caption).foregroundStyle(Palette.textSecondary).frame(width: 110, alignment: .trailing)
                        Image(systemName: "chevron.right").foregroundStyle(Palette.textTertiary)
                    }
                    .padding(.vertical, Space.s)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
    }

    private func load() async {
        data = .loading
        do { data = .loaded(try await environment.insights.teamDashboard(range: period.range)) }
        catch { data = .failed(DashboardViewModel.map(error)) }
    }
}

struct MemberDetailView: View {
    let member: UserTimeItem
    let period: ReportPeriod
    let environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var data: Loadable<IndividualDashboardResponse> = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack {
                InitialsAvatar(initials: String(member.displayName.prefix(1)), size: 40)
                VStack(alignment: .leading) {
                    Text(member.displayName).font(Typo.title)
                    Text(member.email).foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text(period.rawValue).font(Typo.overline).foregroundStyle(Palette.textSecondary)
            LoadStateView(state: data, retry: { Task { await load() } }) { d in
                HStack(spacing: Space.l) {
                    StatTile(label: "Worked", value: Format.duration(d.summary.workedSec))
                    StatTile(label: "On tasks", value: Format.duration(d.summary.taskLoggedSec))
                    StatTile(label: "Meetings", value: Format.duration(d.summary.meetingSec))
                    StatTile(label: "Productive", value: "\(d.summary.productivePct)%")
                }
                if !d.topProjects.isEmpty {
                    Text("Projects").font(Typo.heading)
                    ForEach(d.topProjects) { p in
                        HStack { Text(p.projectName); Spacer(); Text(Format.duration(p.totalSec)).monospacedDigit() }
                    }
                }
            }
        }
        .padding(Space.xl)
        .frame(width: 620)
        .task { await load() }
    }

    private func load() async {
        data = .loading
        do { data = .loaded(try await environment.insights.individualDashboard(range: period.range, userId: member.userId)) }
        catch { data = .failed(DashboardViewModel.map(error)) }
    }
}

// MARK: - Reports

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
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                HStack {
                    Picker("Report", selection: $tab) { ForEach(Tab.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented).frame(maxWidth: 420).labelsHidden()
                    Spacer()
                    if let portal = environment.configuration.portalOrigin {
                        Link(destination: portal) { Label("Export in Web Portal", systemImage: "arrow.up.right.square") }
                            .help("PDF/CSV export uses the portal's report jobs.")
                    }
                }
                PeriodPicker(period: $period)
                switch tab {
                case .productivity: ProductivityReport(environment: environment, period: period)
                case .time: TimeReport(environment: environment, period: period)
                case .attendance: AttendanceReport(environment: environment, period: period)
                case .leave: LeaveReport(environment: environment, period: period, isAdmin: model.role.atLeast(.admin))
                }
            }
            .padding(Space.xl)
            .frame(maxWidth: 1200, alignment: .leading)
        }
    }
}

private struct ProductivityReport: View {
    let environment: AppEnvironment
    let period: ReportPeriod
    @State private var data: Loadable<ProductivityScoreResponse> = .idle

    var body: some View {
        LoadStateView(state: data, emptyTitle: "No activity in this period", emptySymbol: "chart.bar",
                      isEmpty: { $0.days.isEmpty }, retry: { Task { await load() } }) { r in
            StatTile(label: "Average score", value: r.avgScore.formatted(.number.precision(.fractionLength(0))))
            Card("Daily productivity score") {
                Chart(r.days, id: \.date) { day in
                    BarMark(x: .value("Day", day.date.date() ?? Date(), unit: .day), y: .value("Score", day.score))
                        .foregroundStyle(Palette.accent)
                }
                .chartYScale(domain: 0...100)
                .frame(height: 240)
            }
        }
        .task(id: period) { await load() }
    }

    private func load() async {
        data = .loading
        do { data = .loaded(try await environment.insights.productivity(range: period.range)) } catch { data = .failed(DashboardViewModel.map(error)) }
    }
}

private struct TimeReport: View {
    let environment: AppEnvironment
    let period: ReportPeriod
    @State private var projects: Loadable<ProjectTimeSummaryResponse> = .idle
    @State private var tasks: TaskTimeSummaryResponse?

    var body: some View {
        LoadStateView(state: projects, emptyTitle: "No time logged", emptySymbol: "clock",
                      isEmpty: { $0.items.isEmpty }, retry: { Task { await load() } }) { p in
            StatTile(label: "Total logged", value: Format.duration(p.totalDurationSec))
            Card("By project") {
                Chart(Array(p.items.enumerated()), id: \.offset) { pair in
                    BarMark(x: .value("Hours", Double(pair.element.totalDurationSec) / 3600),
                            y: .value("Project", pair.element.projectName ?? "Unassigned"))
                        .foregroundStyle(Palette.accent)
                }
                .frame(height: CGFloat(max(120, p.items.count * 32)))
            }
            if let tasks, !tasks.items.isEmpty {
                Card("By task") {
                    ForEach(Array(tasks.items.enumerated()), id: \.offset) { _, t in
                        HStack {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(t.taskName ?? "Unassigned").font(Typo.bodyEmphasis)
                                Text(t.projectName ?? "").font(Typo.caption).foregroundStyle(Palette.textSecondary)
                            }
                            Spacer()
                            Text(Format.duration(t.totalDurationSec)).monospacedDigit()
                        }
                        Divider()
                    }
                }
            }
        }
        .task(id: period) { await load() }
    }

    private func load() async {
        projects = .loading
        do {
            projects = .loaded(try await environment.work.projectSummary(range: period.range))
            tasks = try? await environment.work.taskSummary(range: period.range)
        } catch { projects = .failed(DashboardViewModel.map(error)) }
    }
}

private struct AttendanceReport: View {
    let environment: AppEnvironment
    let period: ReportPeriod
    @State private var data: Loadable<UtilisationResponse> = .idle

    var body: some View {
        LoadStateView(state: data, emptyTitle: "No attendance data", emptySymbol: "calendar",
                      isEmpty: { $0.days.isEmpty }, retry: { Task { await load() } }) { r in
            StatTile(label: "Average utilisation", value: "\(Int(r.avgUtilisationPct.rounded()))%")
            Card("Active, idle and break time per day") {
                Chart {
                    ForEach(r.days, id: \.date) { d in
                        BarMark(x: .value("Day", d.date.date() ?? Date(), unit: .day), y: .value("Hours", Double(d.activeSec) / 3600))
                            .foregroundStyle(by: .value("Kind", "Active"))
                        BarMark(x: .value("Day", d.date.date() ?? Date(), unit: .day), y: .value("Hours", Double(d.idleSec) / 3600))
                            .foregroundStyle(by: .value("Kind", "Idle"))
                        BarMark(x: .value("Day", d.date.date() ?? Date(), unit: .day), y: .value("Hours", Double(d.breakSec) / 3600))
                            .foregroundStyle(by: .value("Kind", "Break"))
                    }
                }
                .chartForegroundStyleScale(["Active": Palette.success, "Idle": Palette.textTertiary, "Break": Palette.warning])
                .frame(height: 240)
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
    let isAdmin: Bool
    @State private var data: Loadable<[LeaveApplication]> = .idle
    @State private var selected: LeaveApplication?

    var body: some View {
        LoadStateView(state: data, emptyTitle: "No leave in this period", emptySymbol: "calendar.badge.clock",
                      isEmpty: { $0.isEmpty }, retry: { Task { await load() } }) { items in
            let approved = items.filter { $0.statusValue == .approved }
            HStack(spacing: Space.l) {
                StatTile(label: "Requests", value: "\(items.count)")
                StatTile(label: "Approved days", value: Format.days(FlexibleDecimal(approved.reduce(Decimal(0)) { $0 + $1.durationDays.value })))
                StatTile(label: "Pending", value: "\(items.filter { $0.statusValue?.isPending == true }.count)")
            }
            LeaveApplicationTable(items: items, showEmployee: true, selection: $selected)
                .frame(minHeight: 320)
        }
        .task(id: period) { await load() }
        .sheet(item: $selected) { a in
            LeaveDetailView(application: a, environment: environment, mode: .own) {}
        }
    }

    private func load() async {
        data = .loading
        do {
            let r = period.range
            data = .loaded(try await environment.leave.applications(startFrom: r.from, startTo: r.to, pageSize: 200).items)
        } catch { data = .failed(DashboardViewModel.map(error)) }
    }
}

// MARK: - Notifications

struct NotificationsView: View {
    @Environment(AppModel.self) private var model
    @State private var unreadOnly = false
    @State private var data: Loadable<NotificationListResponse> = .idle
    @State private var error: AppError?
    private let service: NotificationService

    init(environment: AppEnvironment) { service = environment.notifications }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Toggle("Unread only", isOn: $unreadOnly).toggleStyle(.switch)
                Spacer()
                Button("Mark All as Read") { Task { await markAll() } }
                    .disabled((data.value?.unreadCount ?? 0) == 0)
            }
            .padding([.horizontal, .top], Space.xl)
            LoadStateView(state: data, emptyTitle: unreadOnly ? "No unread notifications" : "No notifications",
                          emptySymbol: "bell.slash", isEmpty: { $0.items.isEmpty }, retry: { Task { await load() } }) { list in
                List(list.items) { item in
                    HStack(alignment: .top, spacing: Space.m) {
                        Circle().fill(item.isRead ? Color.clear : Palette.accent).frame(width: 8, height: 8).padding(.top, 5)
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            Text(item.title).font(item.isRead ? Typo.body : Typo.bodyEmphasis)
                            Text(item.message).font(Typo.caption).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                            Text(Format.relative(item.createdAt)).font(Typo.caption).foregroundStyle(Palette.textTertiary)
                        }
                        Spacer()
                        if !item.isRead {
                            Button("Mark Read") { Task { await markRead(item) } }.controlSize(.small)
                        }
                    }
                    .padding(.vertical, Space.xs)
                }
                .listStyle(.inset)
            }
        }
        .task(id: unreadOnly) { await load() }
        .alert("Couldn't update notifications", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } }),
               presenting: error) { _ in Button("OK", role: .cancel) {} } message: { Text($0.userMessage) }
    }

    private func load() async {
        if data.value == nil { data = .loading }
        do { data = .loaded(try await service.list(limit: 100, unreadOnly: unreadOnly)) } catch { data = .failed(DashboardViewModel.map(error)) }
        await model.refreshUnreadCount()
    }

    private func markRead(_ item: NotificationItem) async {
        do { _ = try await service.markRead(item.id); await load() } catch { self.error = DashboardViewModel.map(error) }
    }

    private func markAll() async {
        do { _ = try await service.markAllRead(); await load() } catch { self.error = DashboardViewModel.map(error) }
    }
}

// MARK: - Activity (app + domain usage; domains are eTLD+1 only)

struct ActivityView: View {
    @State private var period: ReportPeriod = .today
    @State private var apps: Loadable<AppUsageResponse> = .idle
    @State private var domains: Loadable<DomainUsageResponse> = .idle
    private let insights: InsightsService

    init(environment: AppEnvironment) { insights = environment.insights }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                PeriodPicker(period: $period)
                Text("Only application names and website domains are recorded — never page addresses, content or keystrokes.")
                    .font(Typo.caption).foregroundStyle(Palette.textSecondary)
                HStack(alignment: .top, spacing: Space.l) {
                    Card("Applications") {
                        LoadStateView(state: apps, emptyTitle: "No app activity", emptySymbol: "macwindow",
                                      isEmpty: { $0.items.isEmpty }, retry: { Task { await load() } }) { r in
                            ForEach(r.items, id: \.appName) { item in
                                usageRow(item.appName, category: item.category, seconds: item.durationSec, pct: item.percentage)
                            }
                        }
                    }
                    Card("Websites") {
                        LoadStateView(state: domains, emptyTitle: "No website activity", emptySymbol: "globe",
                                      isEmpty: { $0.items.isEmpty }, retry: { Task { await load() } }) { r in
                            ForEach(r.items, id: \.domain) { item in
                                usageRow(item.domain, category: item.category, seconds: item.totalSec, pct: item.percentage)
                            }
                        }
                    }
                }
            }
            .padding(Space.xl)
            .frame(maxWidth: 1200, alignment: .leading)
        }
        .task(id: period) { await load() }
    }

    private func usageRow(_ name: String, category: String, seconds: Int, pct: Double) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            HStack {
                Text(name).font(Typo.bodyEmphasis).lineLimit(1)
                StatusPill(text: category.capitalized, tone: category == "productive" ? .success : (category == "unproductive" ? .danger : .neutral))
                Spacer()
                Text(Format.duration(seconds)).monospacedDigit()
            }
            ProgressView(value: min(max(pct / 100, 0), 1)).tint(Palette.accent)
        }
        .padding(.vertical, Space.xxs)
    }

    private func load() async {
        apps = .loading
        domains = .loading
        let range = period.range
        let insights = self.insights
        async let a = Result(awaiting: { try await insights.appUsage(range: range, pageSize: 25) })
        async let d = Result(awaiting: { try await insights.domainUsage(range: range, pageSize: 25) })
        switch await a { case .success(let v): apps = .loaded(v); case .failure(let e): apps = .failed(DashboardViewModel.map(e)) }
        switch await d { case .success(let v): domains = .loaded(v); case .failure(let e): domains = .failed(DashboardViewModel.map(e)) }
    }
}

extension Result where Failure == Error {
    /// Async catching initialiser (Swift's `Result(catching:)` is synchronous).
    init(awaiting body: () async throws -> Success) async {
        do { self = .success(try await body()) } catch { self = .failure(error) }
    }
}
