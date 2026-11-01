import SwiftUI
import Observation
import EffiLensKit

// All rules (balance, approval routing, paid/unpaid split, holiday exclusion,
// overlap checks) are enforced by core-services. These screens collect input,
// show server responses and never compute balances locally.

// MARK: - Apply for leave (POST /leave/applications)

struct ApplyLeaveView: View {
    @Environment(AppModel.self) private var model
    @State private var start = Date()
    @State private var end = Date()
    @State private var halfDay = false
    @State private var reason = ""
    @State private var submitting = false
    @State private var error: AppError?
    @State private var submitted: LeaveApplication?
    @State private var balance: LeaveBalance?
    private let leave: LeaveService
    let onNavigate: (Route) -> Void

    init(environment: AppEnvironment, onNavigate: @escaping (Route) -> Void) {
        leave = environment.leave
        self.onNavigate = onNavigate
    }

    private var startDay: CalendarDate { CalendarDate(start) }
    private var endDay: CalendarDate { CalendarDate(halfDay ? start : end) }
    private var validation: String? {
        if endDay < startDay { return "End date must be on or after the start date." }
        if reason.count > 1000 { return "Reason is too long (1000 characters max)." }
        return nil
    }

    var body: some View {
        Form {
            if let balance {
                Section {
                    LabeledContent("Paid leave remaining", value: "\(Format.days(balance.paidRemaining)) days")
                    LabeledContent("Comp-off remaining", value: "\(Format.days(balance.compOffRemaining)) days")
                } footer: {
                    Text("If paid leave runs out, the remainder is recorded as unpaid. The server decides the split.")
                }
            }
            Section("Dates") {
                DatePicker("From", selection: $start, displayedComponents: .date)
                Toggle("Half day", isOn: $halfDay)
                if !halfDay {
                    DatePicker("To", selection: $end, in: start..., displayedComponents: .date)
                }
                LabeledContent("Requested", value: Format.dateRange(startDay, endDay))
            }
            Section("Reason (optional)") {
                TextEditor(text: $reason).frame(minHeight: 80).font(Typo.body)
            }
            Section {
                if let validation { Text(validation).font(Typo.caption).foregroundStyle(Palette.danger) }
                if let error { Label(error.userMessage, systemImage: "exclamationmark.circle").foregroundStyle(Palette.danger) }
                if let submitted {
                    Label(submitted.message ?? "Request submitted — \(submitted.statusValue?.displayName ?? submitted.status).",
                          systemImage: "checkmark.circle")
                        .foregroundStyle(Palette.success)
                    Button("View My Requests") { onNavigate(.myRequests) }
                }
                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        if submitting { ProgressView().controlSize(.small) }
                        Text("Submit Request")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(validation != nil || submitting)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 640)
        .onChange(of: start) { _, newValue in if end < newValue { end = newValue } }
        .task { balance = try? await leave.balance(year: Calendar.current.component(.year, from: start)) }
    }

    private func submit() async {
        submitting = true
        error = nil
        defer { submitting = false }
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            submitted = try await leave.apply(LeaveApplicationCreate(startDate: startDay, endDate: endDay, halfDay: halfDay,
                                                                    reason: trimmed.isEmpty ? nil : trimmed))
            reason = ""
        } catch {
            self.error = DashboardViewModel.map(error)
        }
    }
}

// MARK: - My requests + detail

@MainActor
@Observable
final class LeaveRequestsViewModel {
    var statusFilter: LeaveStatus?
    private(set) var list: Loadable<[LeaveApplication]> = .idle
    var actionError: AppError?
    private let leave: LeaveService
    let ownUserId: UUID?

    init(environment: AppEnvironment, ownUserId: UUID?) {
        leave = environment.leave
        self.ownUserId = ownUserId
    }

    func load() async {
        list = .loading
        do {
            // Own requests only — managers see team requests under Approvals.
            let page = try await leave.applications(userId: ownUserId, status: statusFilter, pageSize: 200)
            list = .loaded(page.items.sorted { $0.startDate > $1.startDate })
        } catch { list = .failed(DashboardViewModel.map(error)) }
    }

    func withdraw(_ application: LeaveApplication) async {
        do { _ = try await leave.cancel(application.id); await load() } catch { actionError = DashboardViewModel.map(error) }
    }
}

struct LeaveRequestsView: View {
    @State private var viewModel: LeaveRequestsViewModel
    @State private var selected: LeaveApplication?
    private let environment: AppEnvironment

    init(environment: AppEnvironment, ownUserId: UUID?) {
        self.environment = environment
        _viewModel = State(initialValue: LeaveRequestsViewModel(environment: environment, ownUserId: ownUserId))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Picker("Status", selection: $viewModel.statusFilter) {
                Text("All").tag(LeaveStatus?.none)
                ForEach(LeaveStatus.allCases, id: \.self) { Text($0.displayName).tag(Optional($0)) }
            }
            .frame(maxWidth: 260)
            .padding([.horizontal, .top], Space.xl)

            LoadStateView(state: viewModel.list, emptyTitle: "No leave requests", emptyMessage: "Requests you submit appear here.",
                          emptySymbol: "tray", isEmpty: { $0.isEmpty }, retry: { Task { await viewModel.load() } }) { items in
                LeaveApplicationTable(items: items, showEmployee: false, selection: $selected)
            }
        }
        .task(id: viewModel.statusFilter) { await viewModel.load() }
        .sheet(item: $selected) { application in
            LeaveDetailView(application: application, environment: environment, mode: .own) {
                Task { await viewModel.load() }
            }
        }
    }
}

struct LeaveApplicationTable: View {
    let items: [LeaveApplication]
    let showEmployee: Bool
    @Binding var selection: LeaveApplication?

    var body: some View {
        Table(items) {
            TableColumn("Dates") { a in Text(Format.dateRange(a.startDate, a.endDate)) }
            TableColumn("Employee") { a in Text(showEmployee ? (a.userDisplayName ?? a.userEmail ?? "—") : "You") }
            TableColumn("Days") { a in Text(Format.days(a.durationDays)).monospacedDigit() }.width(50)
            TableColumn("Type") { a in Text(a.kind?.displayName ?? a.leaveType.capitalized) }.width(100)
            TableColumn("Status") { a in LeaveStatusPill(status: a.statusValue) }.width(140)
            TableColumn("") { a in Button("Details") { selection = a }.controlSize(.small) }.width(80)
        }
    }
}

struct LeaveDetailView: View {
    enum Mode { case own, managerReview, adminReview }

    let application: LeaveApplication
    let environment: AppEnvironment
    let mode: Mode
    var onChange: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rejectReason = ""
    @State private var working = false
    @State private var error: AppError?
    @State private var confirmWithdraw = false

    private var leave: LeaveService { environment.leave }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack {
                Text("Leave request").font(Typo.title)
                Spacer()
                LeaveStatusPill(status: application.statusValue)
            }
            Grid(alignment: .leading, horizontalSpacing: Space.l, verticalSpacing: Space.s) {
                row("Employee", application.userDisplayName ?? application.userEmail ?? "You")
                row("Dates", Format.dateRange(application.startDate, application.endDate))
                row("Duration", "\(Format.days(application.durationDays)) day(s)")
                row("Paid / unpaid", "\(Format.days(application.paidDays)) / \(Format.days(application.unpaidDays))")
                row("Type", application.kind?.displayName ?? application.leaveType)
                row("Source", application.sourceValue?.displayName ?? application.source)
                row("Submitted", application.createdAt.formatted(date: .abbreviated, time: .shortened))
                if let reason = application.reason, !reason.isEmpty { row("Reason", reason) }
                if let rejection = application.rejectionReason { row("Rejection reason", rejection) }
                if let at = application.managerApprovedAt { row("Manager approved", at.formatted(date: .abbreviated, time: .shortened)) }
                if let at = application.adminApprovedAt { row("Admin approved", at.formatted(date: .abbreviated, time: .shortened)) }
            }

            if mode != .own, application.statusValue?.isPending == true {
                TextField("Reason for rejection (required to reject)", text: $rejectReason, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(2...4)
            }
            if let error { Label(error.userMessage, systemImage: "exclamationmark.circle").foregroundStyle(Palette.danger) }

            HStack {
                if mode == .own, application.isWithdrawable {
                    Button("Withdraw Request", role: .destructive) { confirmWithdraw = true }
                }
                Spacer()
                if working { ProgressView().controlSize(.small) }
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                if mode != .own, application.statusValue?.isPending == true {
                    Button("Reject", role: .destructive) { Task { await act(approve: false) } }
                        .disabled(rejectReason.trimmingCharacters(in: .whitespaces).isEmpty || working)
                    Button("Approve") { Task { await act(approve: true) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(working)
                }
            }
        }
        .padding(Space.xl)
        .frame(width: 520)
        .confirmationDialog("Withdraw this leave request?", isPresented: $confirmWithdraw) {
            Button("Withdraw", role: .destructive) { Task { await withdraw() } }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).font(Typo.caption).foregroundStyle(Palette.textSecondary)
            Text(value).font(Typo.body).textSelection(.enabled)
        }
    }

    private func withdraw() async {
        working = true
        defer { working = false }
        do { _ = try await leave.cancel(application.id); onChange(); dismiss() } catch { self.error = DashboardViewModel.map(error) }
    }

    private func act(approve: Bool) async {
        working = true
        defer { working = false }
        let reason = rejectReason.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            switch (mode, approve) {
            case (.managerReview, true): _ = try await leave.managerApprove(application)
            case (.managerReview, false): _ = try await leave.managerReject(application.id, reason: reason)
            case (.adminReview, true): _ = try await leave.adminApprove(application.id)
            case (.adminReview, false): _ = try await leave.adminReject(application.id, reason: reason)
            case (.own, _): return
            }
            onChange()
            dismiss()
        } catch {
            self.error = DashboardViewModel.map(error)
        }
    }
}

// MARK: - Leave calendar (GET /leave/calendar)

struct LeaveCalendarView: View {
    @State private var month = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var data: Loadable<LeaveCalendar> = .idle
    private let leave: LeaveService

    init(environment: AppEnvironment) { leave = environment.leave }

    private var comps: (year: Int, month: Int) {
        let c = Calendar.current.dateComponents([.year, .month], from: month)
        return (c.year ?? 2026, c.month ?? 1)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous month")
                    Text(month.formatted(.dateTime.month(.wide).year())).font(Typo.title).frame(minWidth: 200)
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next month")
                    Spacer()
                    Button("Today") { month = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date() }
                }
                LoadStateView(state: data, retry: { Task { await load() } }) { cal in
                    HStack(spacing: Space.l) {
                        StatTile(label: "Leave days this month", value: Format.days(cal.monthLeaveCount))
                        StatTile(label: "Holidays", value: "\(cal.holidayCount)")
                    }
                    MonthGrid(month: month, days: cal.days)
                    legend
                }
            }
            .padding(Space.xl)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .task(id: month) { await load() }
    }

    private func shift(_ delta: Int) {
        if let d = Calendar.current.date(byAdding: .month, value: delta, to: month) { month = d }
    }

    private func load() async {
        data = .loading
        do { data = .loaded(try await leave.calendar(year: comps.year, month: comps.month)) }
        catch { data = .failed(DashboardViewModel.map(error)) }
    }

    private var legend: some View {
        HStack(spacing: Space.l) {
            legendItem(Palette.accent, "Leave")
            legendItem(Palette.warning, "Pending")
            legendItem(Palette.info, "Holiday")
            legendItem(Palette.textTertiary, "Weekend")
        }
        .font(Typo.caption)
    }

    private func legendItem(_ color: Color, _ text: String) -> some View {
        HStack(spacing: Space.xs) { Circle().fill(color).frame(width: 8, height: 8); Text(text) }
    }
}

struct MonthGrid: View {
    let month: Date
    let days: [LeaveCalendarDay]

    private var leading: Int {
        let cal = Calendar.current
        let firstWeekday = cal.component(.weekday, from: month)
        return (firstWeekday - cal.firstWeekday + 7) % 7
    }

    private var symbols: [String] {
        let cal = Calendar.current
        let all = cal.veryShortStandaloneWeekdaySymbols
        let pivot = max(0, min(all.count, cal.firstWeekday - 1))
        return Array(all[pivot...]) + Array(all[..<pivot])
    }

    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: Space.xs), count: 7) }

    var body: some View {
        LazyVGrid(columns: columns, spacing: Space.xs) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, s in
                Text(s).font(Typo.overline).foregroundStyle(Palette.textSecondary)
            }
            ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 64) }
            ForEach(days, id: \.date) { day in DayCell(day: day) }
        }
    }
}

private struct DayCell: View {
    let day: LeaveCalendarDay

    private var tint: Color? {
        if day.isLeave { return LeaveStatus(rawValue: day.leaveStatus ?? "")?.isPending == true ? Palette.warning : Palette.accent }
        if day.isHoliday { return Palette.info }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text("\(day.date.day)").font(Typo.bodyEmphasis)
                .foregroundStyle(day.isWeekend ? Palette.textTertiary : Palette.textPrimary)
            if let name = day.holidayName { Text(name).font(.system(size: 10)).lineLimit(2).foregroundStyle(Palette.info) }
            if day.isLeave { Text(day.isHalfDay ? "Half day" : "Leave").font(.system(size: 10)).foregroundStyle(tint ?? Palette.accent) }
            Spacer(minLength: 0)
        }
        .padding(Space.xs)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .background((tint ?? Palette.inset).opacity(tint == nil ? 1 : 0.14), in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Holidays (GET /leave/holidays, claim comp-off / apply leave)

struct HolidaysView: View {
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var holidays: Loadable<[Holiday]> = .idle
    @State private var actionError: AppError?
    @State private var actionMessage: String?
    @State private var working: UUID?
    private let leave: LeaveService

    init(environment: AppEnvironment) { leave = environment.leave }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Stepper("Year \(year.formatted(.number.grouping(.never)))", value: $year, in: 2020...2100)
                Spacer()
                if let actionMessage { Label(actionMessage, systemImage: "checkmark.circle").foregroundStyle(Palette.success).font(Typo.caption) }
            }
            .padding([.horizontal, .top], Space.xl)
            LoadStateView(state: holidays, emptyTitle: "No holidays", emptyMessage: "Your organisation hasn't published holidays for this year.",
                          emptySymbol: "sun.max", isEmpty: { $0.isEmpty }, retry: { Task { await load() } }) { items in
                Table(items) {
                    TableColumn("Date") { h in Text(h.date.date()?.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) ?? h.date.description) }
                        .width(120)
                    TableColumn("Holiday") { h in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(h.name).font(Typo.bodyEmphasis)
                            if let d = h.description, !d.isEmpty { Text(d).font(Typo.caption).foregroundStyle(Palette.textSecondary) }
                        }
                    }
                    TableColumn("Status") { h in
                        if h.userCompoffClaimed == true { StatusPill(text: "Comp-off claimed", tone: .success) }
                        else if h.userLeaveApplied == true { StatusPill(text: "Leave applied", tone: .info) }
                        else if h.date < CalendarDate(Date()) { StatusPill(text: "Past", tone: .neutral) }
                        else { StatusPill(text: "Upcoming", tone: .accent) }
                    }
                    .width(150)
                    TableColumn("") { h in
                        if working == h.id { ProgressView().controlSize(.small) }
                        else if h.userCompoffClaimed != true && h.userLeaveApplied != true {
                            Menu("Actions") {
                                Button("Claim Comp-off (worked this day)") { Task { await act(h, compOff: true) } }
                                Button("Apply Leave for This Holiday") { Task { await act(h, compOff: false) } }
                            }
                            .controlSize(.small)
                            .fixedSize()
                        }
                    }
                    .width(110)
                }
            }
        }
        .task(id: year) { await load() }
        .alert("Action failed", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } }),
               presenting: actionError) { _ in Button("OK", role: .cancel) {} } message: { Text($0.userMessage) }
    }

    private func load() async {
        holidays = .loading
        do { holidays = .loaded(try await leave.holidays(year: year).sorted { $0.date < $1.date }) }
        catch { holidays = .failed(DashboardViewModel.map(error)) }
    }

    private func act(_ holiday: Holiday, compOff: Bool) async {
        working = holiday.id
        defer { working = nil }
        do {
            let result: LeaveApplication
            if compOff {
                result = try await leave.claimCompOff(holidayId: holiday.id, reason: nil)
            } else {
                result = try await leave.applyHolidayLeave(holidayId: holiday.id, reason: nil)
            }
            actionMessage = result.message ?? "Request submitted for approval."
            await load()
        } catch {
            actionError = DashboardViewModel.map(error)
        }
    }
}

// MARK: - Leave balance (GET /leave/balance + /leave/policy/me)

struct LeaveBalanceView: View {
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var balance: Loadable<LeaveBalance> = .idle
    @State private var policy: EffectiveLeavePolicy?
    private let leave: LeaveService

    init(environment: AppEnvironment) { leave = environment.leave }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                Stepper("Year \(year.formatted(.number.grouping(.never)))", value: $year, in: 2020...2100).frame(maxWidth: 220)
                LoadStateView(state: balance, retry: { Task { await load() } }) { b in
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: Space.l)], spacing: Space.l) {
                        StatTile(label: "Paid allocated", value: Format.days(b.paidAllocated))
                        StatTile(label: "Paid used", value: Format.days(b.paidUsed))
                        StatTile(label: "Paid remaining", value: Format.days(b.paidRemaining),
                                 progress: b.paidAllocated.doubleValue > 0 ? (b.paidRemaining?.doubleValue ?? 0) / b.paidAllocated.doubleValue : nil)
                        StatTile(label: "Carried forward", value: Format.days(b.carryForward))
                        StatTile(label: "Unpaid used", value: Format.days(b.unpaidUsed))
                        StatTile(label: "Comp-off earned", value: Format.days(b.compOffBalance))
                        StatTile(label: "Comp-off used", value: Format.days(b.compOffUsed))
                        StatTile(label: "Comp-off remaining", value: Format.days(b.compOffRemaining))
                        StatTile(label: "Total leave taken", value: Format.days(b.totalLeaveTaken))
                        if let h = b.holidaysInYear { StatTile(label: "Holidays this year", value: "\(h)") }
                    }
                }
                if let policy {
                    Card("Your policy", subtitle: policy.hasUserOverride ? "Includes a personal override" : (policy.hasGroupOverride ? "Includes a group override" : nil)) {
                        Grid(alignment: .leading, horizontalSpacing: Space.xl, verticalSpacing: Space.s) {
                            GridRow { Text("Paid leave per year").foregroundStyle(Palette.textSecondary); Text("\(policy.paidLeaveDaysPerYear) days") }
                            GridRow { Text("Weekly hours required").foregroundStyle(Palette.textSecondary); Text("\(Format.days(policy.weeklyRequiredHours)) h") }
                            GridRow { Text("Working days per week").foregroundStyle(Palette.textSecondary); Text("\(policy.weeklyWorkingDays)") }
                            GridRow { Text("Daily minimum").foregroundStyle(Palette.textSecondary); Text("\(Format.days(policy.dailyMinHours)) h") }
                            if let limit = policy.monthlyLeaveLimit { GridRow { Text("Monthly leave limit").foregroundStyle(Palette.textSecondary); Text("\(Format.days(limit)) days") } }
                            if let carry = policy.carryForwardLimit { GridRow { Text("Carry-forward limit").foregroundStyle(Palette.textSecondary); Text("\(carry) days") } }
                        }
                        .font(Typo.body)
                    }
                }
            }
            .padding(Space.xl)
            .frame(maxWidth: 1000, alignment: .leading)
        }
        .task(id: year) { await load() }
        .task { policy = try? await leave.myPolicy() }
    }

    private func load() async {
        balance = .loading
        do { balance = .loaded(try await leave.balance(year: year)) } catch { balance = .failed(DashboardViewModel.map(error)) }
    }
}
