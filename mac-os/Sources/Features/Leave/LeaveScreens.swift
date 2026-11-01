import SwiftUI
import Observation
import EffiLensKit

// All rules (balance, approval routing, paid/unpaid split, holiday exclusion,
// overlap checks) are enforced by core-services. These screens collect input,
// show server responses and never compute balances locally.

// MARK: - Apply for leave (prototype V.apply: 1.3 : 1; POST /leave/applications)

struct ApplyLeaveView: View {
    @Environment(Navigator.self) private var navigator
    @State private var start = Date()
    @State private var end = Date()
    @State private var halfDay = false
    @State private var reason = ""
    @State private var submitting = false
    @State private var error: AppError?
    @State private var submitted: LeaveApplication?
    @State private var balance: LeaveBalance?
    @State private var managerName: String?
    private let leave: LeaveService
    private let profile: ProfileService
    let onNavigate: (Route) -> Void

    init(environment: AppEnvironment, onNavigate: @escaping (Route) -> Void) {
        leave = environment.leave
        profile = environment.profile
        self.onNavigate = onNavigate
    }

    private var startDay: CalendarDate { CalendarDate(start) }
    private var endDay: CalendarDate { CalendarDate(halfDay ? start : end) }
    private var calendarDays: Int {
        let cal = Calendar.current
        return (cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: halfDay ? start : end)).day ?? 0) + 1
    }
    private var validation: String? {
        if endDay < startDay { return "End date must be on or after the start date." }
        if reason.count > 1000 { return "Reason is too long (1000 characters max)." }
        return nil
    }

    var body: some View {
        Page {
            FractionalColumns(ratio: 1.3) {
                Card("Leave request") {
                    VStack(alignment: .leading, spacing: 0) {
                        FieldLabel("Leave type").padding(.top, -12)
                        HStack(spacing: 8) {
                            EffiSegmented(selection: .constant(0), options: [(0, "Paid leave")])
                            Text("Paid or unpaid is decided by your balance.").font(Typo.caption).foregroundStyle(Palette.textTertiary)
                        }
                        EqualColumns(count: 2, spacing: 10) {
                            VStack(alignment: .leading, spacing: 0) {
                                FieldLabel("From")
                                FieldChrome { DatePicker("From", selection: $start, displayedComponents: .date).datePickerStyle(.field) }
                            }
                            VStack(alignment: .leading, spacing: 0) {
                                FieldLabel("To")
                                FieldChrome { DatePicker("To", selection: $end, in: start..., displayedComponents: .date).datePickerStyle(.field) }
                                    .disabled(halfDay)
                            }
                        }
                        FieldLabel("Duration")
                        EffiSegmented(selection: $halfDay, options: [(false, "Full day"), (true, "Half day")])
                        FieldLabel("Reason")
                        EffiTextArea(placeholder: "Brief reason for your manager", text: $reason)
                        FieldLabel("Approver")
                        HStack(spacing: 6) {
                            Pill(text: managerName.map { "\($0) (Manager)" } ?? "Your manager", kind: .blue)
                        }
                        Group {
                            if let validation { Text(validation).foregroundStyle(Palette.danger) }
                            else if let error { Text(error.userMessage).foregroundStyle(Palette.danger) }
                            else if let submitted {
                                HStack {
                                    Text(submitted.message ?? "Request submitted — \(submitted.statusValue?.displayName ?? submitted.status).").foregroundStyle(Palette.success)
                                    CardLink("View request") { navigator.leaveDetail = LeaveDetailContext(application: submitted, mode: .own, back: .myRequests) }
                                }
                            }
                        }
                        .font(.system(size: 12))
                        .padding(.top, 10)
                        HStack {
                            Spacer()
                            Button("Cancel") { onNavigate(.leaveOverview) }.buttonStyle(.effi)
                            Button {
                                Task { await submit() }
                            } label: {
                                HStack(spacing: 6) {
                                    if submitting { ProgressView().controlSize(.small) }
                                    Text("Submit Request")
                                }
                            }
                            .buttonStyle(.effiPrimary)
                            .keyboardShortcut(.defaultAction)
                            .disabled(validation != nil || submitting)
                        }
                        .padding(.top, 14)
                    }
                }
                summary
            }
        }
        .onChange(of: start) { _, newValue in if end < newValue { end = newValue } }
        .task {
            balance = try? await leave.balance(year: Calendar.current.component(.year, from: start))
            managerName = try? await profile.profile().managerName
        }
    }

    private var summary: some View {
        Card("Summary") {
            VStack(spacing: 10) {
                let total = balance?.paidAllocated.doubleValue ?? 0
                let remaining = balance?.paidRemaining?.doubleValue ?? 0
                ProgressRing(progress: total > 0 ? remaining / total : 0, lineWidth: 10) {
                    VStack(spacing: 0) {
                        Text(halfDay ? "½" : "\(calendarDays)").font(.system(size: 26, weight: .semibold, design: .monospaced))
                        Text(halfDay ? "day" : "calendar day\(calendarDays == 1 ? "" : "s")").font(.system(size: 10.5)).foregroundStyle(Palette.textTertiary)
                    }
                }
                .frame(width: 130, height: 130)
                .padding(.vertical, 10)
                Text(Format.dateRange(startDay, endDay)).font(Typo.bodyEmphasis)
                Text(balance.map { "\(Format.days($0.paidRemaining)) paid days remaining. Weekends and holidays are excluded by the server; any shortfall is recorded as unpaid." }
                     ?? "Loading your balance…")
                    .font(Typo.body).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center).lineSpacing(3)
            }
            .frame(maxWidth: .infinity)
        }
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

// MARK: - My requests (prototype V.requests)

@MainActor
@Observable
final class LeaveRequestsViewModel {
    enum Filter: String, CaseIterable { case all = "All", pending = "Pending", approved = "Approved", rejected = "Rejected", cancelled = "Cancelled" }
    var filter: Filter = .all
    private(set) var list: Loadable<[LeaveApplication]> = .idle
    private let leave: LeaveService
    let ownUserId: UUID?

    init(environment: AppEnvironment, ownUserId: UUID?) {
        leave = environment.leave
        self.ownUserId = ownUserId
    }

    var filtered: [LeaveApplication] {
        let items = list.value ?? []
        switch filter {
        case .all: return items
        case .pending: return items.filter { $0.statusValue?.isPending == true }
        case .approved: return items.filter { $0.statusValue == .approved }
        case .rejected: return items.filter { $0.statusValue == .rejected }
        case .cancelled: return items.filter { $0.statusValue == .cancelled }
        }
    }

    func load() async {
        if list.value == nil { list = .loading }
        do {
            // Own requests only — managers review team requests under Approvals.
            let page = try await leave.applications(userId: ownUserId, pageSize: 200)
            list = .loaded(page.items.sorted { $0.startDate > $1.startDate })
        } catch { list = .failed(DashboardViewModel.map(error)) }
    }
}

struct LeaveRequestsView: View {
    @Environment(Navigator.self) private var navigator
    @State private var viewModel: LeaveRequestsViewModel

    init(environment: AppEnvironment, ownUserId: UUID?) {
        _viewModel = State(initialValue: LeaveRequestsViewModel(environment: environment, ownUserId: ownUserId))
    }

    var body: some View {
        Page {
            HStack {
                EffiSegmented(selection: $viewModel.filter, options: LeaveRequestsViewModel.Filter.allCases.map { ($0, $0.rawValue) })
                Spacer()
                Button("+ New Request") { navigator.go(.applyLeave) }.buttonStyle(.effiPrimary)
            }
            Card(padding: 6) {
                LoadStateView(state: viewModel.list, retry: { Task { await viewModel.load() } }) { _ in
                    if viewModel.filtered.isEmpty {
                        EmptyStateView(title: "No requests in this category.", symbol: "tray")
                    } else {
                        LeaveApplicationTable(items: viewModel.filtered, showEmployee: false) { a in
                            navigator.leaveDetail = LeaveDetailContext(application: a, mode: .own, back: .myRequests)
                        }
                    }
                }
            }
        }
        .task { await viewModel.load() }
    }
}

struct LeaveApplicationTable: View {
    let items: [LeaveApplication]
    let showEmployee: Bool
    var onSelect: (LeaveApplication) -> Void

    var body: some View {
        EffiTable<LeaveApplication>(rows: items, columns: columns, onSelect: onSelect)
    }

    private var columns: [EffiTable<LeaveApplication>.Column] {
        var cols: [EffiTable<LeaveApplication>.Column] = []
        if showEmployee {
            cols.append(.init("Employee") { a in Text(a.userDisplayName ?? a.userEmail ?? "—").font(Typo.bodyEmphasis) })
        }
        cols.append(.init("Type") { a in Text(a.kind?.displayName ?? a.leaveType.capitalized).font(Typo.bodyEmphasis) })
        cols.append(.init("Dates") { a in Text(Format.dateRange(a.startDate, a.endDate)) })
        cols.append(.init("Days", width: 60) { a in Text(Format.days(a.durationDays)).font(Typo.mono) })
        cols.append(.init("Applied", width: 110) { a in Text(a.createdAt.formatted(.dateTime.day().month(.abbreviated))).foregroundStyle(Palette.textSecondary) })
        cols.append(.init("Status", width: 150) { a in LeaveStatusPill(status: a.statusValue) })
        cols.append(.init("", width: 30) { _ in Text("›").foregroundStyle(Palette.textTertiary) })
        return cols
    }
}

// MARK: - Request details page (prototype V.detail)

struct LeaveDetailView: View {
    enum Mode: Equatable { case own, managerReview, adminReview }

    let application: LeaveApplication
    let environment: AppEnvironment
    let mode: Mode
    /// Returns to the previous screen (and lets it reload).
    var onClose: () -> Void
    @State private var rejectReason = ""
    @State private var working = false
    @State private var error: AppError?
    @State private var confirmWithdraw = false

    private var leave: LeaveService { environment.leave }
    private var backTitle: String { mode == .own ? "‹ My Requests" : "‹ Back" }

    var body: some View {
        Page {
            HStack { Button(backTitle, action: onClose).buttonStyle(.effi) }
            FractionalColumns(ratio: 1.3) {
                Card {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(application.userDisplayName ?? "Your request").font(Typo.mono).foregroundStyle(Palette.textTertiary)
                            Text("\(application.kind?.displayName ?? application.leaveType.capitalized) leave").font(Typo.pageTitle)
                        }
                        Spacer()
                        LeaveStatusPill(status: application.statusValue)
                    }
                    EqualColumns(count: 3) {
                        fact("From", application.startDate.date()?.formatted(date: .abbreviated, time: .omitted) ?? application.startDate.description)
                        fact("To", application.endDate.date()?.formatted(date: .abbreviated, time: .omitted) ?? application.endDate.description)
                        fact("Duration", "\(Format.days(application.durationDays)) working day\(application.durationDays.doubleValue == 1 ? "" : "s")")
                    }
                    .padding(.top, 18)
                    EqualColumns(count: 3) {
                        fact("Paid", "\(Format.days(application.paidDays)) d")
                        fact("Unpaid", "\(Format.days(application.unpaidDays)) d")
                        fact("Source", application.sourceValue?.displayName ?? application.source)
                    }
                    .padding(.top, 10)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reason").font(Typo.small).foregroundStyle(Palette.textTertiary)
                        Text(application.reason?.isEmpty == false ? application.reason! : "No reason given").font(Typo.body).textSelection(.enabled)
                    }
                    .padding(.top, 16)
                    actions.padding(.top, 20)
                    if let error { Text(error.userMessage).font(.system(size: 12)).foregroundStyle(Palette.danger) }
                }
                Card("Approval history") {
                    VStack(alignment: .leading, spacing: 0) {
                        let steps = timeline
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            TimelineItem(tone: step.tone, isLast: index == steps.count - 1) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(step.title).font(Typo.bodyEmphasis)
                                    if let detail = step.detail { Text(detail).font(Typo.caption).foregroundStyle(Palette.textTertiary).fixedSize(horizontal: false, vertical: true) }
                                }
                            }
                        }
                    }
                }
            }
        }
        .confirmationDialog("Withdraw this leave request?", isPresented: $confirmWithdraw) {
            Button("Withdraw", role: .destructive) { Task { await withdraw() } }
        } message: {
            Text("\(Format.dateRange(application.startDate, application.endDate)) · \(Format.days(application.durationDays)) day(s). Your approver will be notified.")
        }
    }

    @ViewBuilder
    private var actions: some View {
        if mode == .own {
            if application.isWithdrawable {
                Button("Withdraw Request") { confirmWithdraw = true }.buttonStyle(.effiDanger).disabled(working)
            }
        } else if application.statusValue?.isPending == true {
            VStack(alignment: .leading, spacing: 8) {
                EffiTextArea(placeholder: "Reason for rejection (required to reject)", text: $rejectReason, height: 56)
                HStack {
                    if working { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("Reject") { Task { await act(approve: false) } }
                        .buttonStyle(.effiDanger)
                        .disabled(rejectReason.trimmingCharacters(in: .whitespaces).isEmpty || working)
                    Button("Approve") { Task { await act(approve: true) } }
                        .buttonStyle(.effiPrimary)
                        .disabled(working)
                }
            }
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Typo.small).foregroundStyle(Palette.textTertiary)
            Text(value).font(Typo.bodyEmphasis)
        }
    }

    private struct Step {
        let title: String
        let detail: String?
        let tone: TimelineTone
    }

    private var timeline: [Step] {
        let fmt: (Date) -> String = { $0.formatted(date: .abbreviated, time: .shortened) }
        var steps = [Step(title: "Submitted", detail: fmt(application.createdAt), tone: .accent)]
        if let at = application.managerApprovedAt { steps.append(Step(title: "Approved by manager", detail: fmt(at), tone: .ok)) }
        if let at = application.managerRejectedAt { steps.append(Step(title: "Rejected by manager", detail: [fmt(at), application.managerRejectionReason.map { "“\($0)”" }].compactMap { $0 }.joined(separator: " · "), tone: .no)) }
        if let at = application.adminApprovedAt { steps.append(Step(title: "Approved by administrator", detail: fmt(at), tone: .ok)) }
        if let at = application.adminRejectedAt { steps.append(Step(title: "Rejected by administrator", detail: [fmt(at), application.adminRejectionReason.map { "“\($0)”" }].compactMap { $0 }.joined(separator: " · "), tone: .no)) }
        switch application.statusValue {
        case .pendingManager: steps.append(Step(title: "Awaiting manager", detail: "Manager review", tone: .accent))
        case .pendingAdmin: steps.append(Step(title: "Awaiting administrator", detail: "Final approval", tone: .accent))
        case .cancelled: steps.append(Step(title: "Withdrawn", detail: fmt(application.updatedAt), tone: .no))
        default: break
        }
        return steps
    }

    private func withdraw() async {
        working = true
        defer { working = false }
        do { _ = try await leave.cancel(application.id); onClose() } catch { self.error = DashboardViewModel.map(error) }
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
            onClose()
        } catch {
            self.error = DashboardViewModel.map(error)
        }
    }
}

// MARK: - Leave calendar (prototype calView; GET /leave/calendar)

@MainActor
@Observable
final class MonthCalendarModel {
    var month: Date = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    private(set) var data: Loadable<LeaveCalendar> = .idle
    private let leave: LeaveService

    init(environment: AppEnvironment) { leave = environment.leave }

    func shift(_ delta: Int) {
        if let d = Calendar.current.date(byAdding: .month, value: delta, to: month) { month = d }
    }

    func goToday() { month = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date() }

    func load() async {
        let c = Calendar.current.dateComponents([.year, .month], from: month)
        data = .loading
        do { data = .loaded(try await leave.calendar(year: c.year ?? 2026, month: c.month ?? 1)) }
        catch { data = .failed(DashboardViewModel.map(error)) }
    }
}

struct LeaveCalendarCard: View {
    @Bindable var model: MonthCalendarModel
    var showLeave = true

    var body: some View {
        Card {
            HStack {
                (Text(model.month.formatted(.dateTime.month(.wide))).font(Typo.serif(28))
                 + Text(" \(model.month.formatted(.dateTime.year()))").font(Typo.serif(28)).foregroundColor(Palette.textTertiary))
                Spacer()
                Button("‹") { model.shift(-1) }.buttonStyle(.effi).accessibilityLabel("Previous month")
                Button("Today") { model.goToday() }.buttonStyle(.effi)
                Button("›") { model.shift(1) }.buttonStyle(.effi).accessibilityLabel("Next month")
            }
            .padding(.bottom, 2)
            if showLeave {
                HStack(spacing: 6) {
                    EventChip(text: "● You · approved", kind: .me)
                    EventChip(text: "● You · pending", kind: .pending)
                    EventChip(text: "● Holiday", kind: .holiday)
                }
            }
            if case .failed(let error) = model.data {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(Palette.danger)
                    Text("Leave and holidays couldn't load — \(error.userMessage)").foregroundStyle(Palette.textSecondary)
                    Button("Retry") { Task { await model.load() } }.buttonStyle(.plain).foregroundStyle(Palette.accentText)
                }
                .font(Typo.caption)
            }
            // The month grid is the calendar itself; server data only adds events.
            MonthGrid(month: model.month, days: model.data.value?.days ?? [], showLeave: showLeave)
        }
        .task(id: model.month) { await model.load() }
    }
}

struct EventChip: View {
    enum Kind { case me, pending, holiday }
    let text: String
    let kind: Kind

    private var color: Color {
        switch kind {
        case .me: return Palette.accentText
        case .pending: return Palette.warning
        case .holiday: return Palette.success
        }
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color.opacity(0.2), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

struct LeaveCalendarView: View {
    @State private var model: MonthCalendarModel

    init(environment: AppEnvironment) { _model = State(initialValue: MonthCalendarModel(environment: environment)) }

    var body: some View {
        Page {
            LeaveCalendarCard(model: model)
            if let cal = model.data.value {
                EqualColumns(count: 2) {
                    StatTile(label: "Leave days this month", value: Format.days(cal.monthLeaveCount))
                    StatTile(label: "Holidays this month", value: "\(cal.holidayCount)")
                }
            }
            Text("Team members' leave is not available to the desktop app yet.").font(Typo.caption).foregroundStyle(Palette.textTertiary)
        }
    }
}

/// `.cal` — 7 columns, 4 pt gap, weekday headers, day cells (min 74, radius 8).
/// Dates come from the calendar; `days` (server) only adds holiday/leave events.
struct MonthGrid: View {
    let month: Date
    let days: [LeaveCalendarDay]
    var showLeave = true

    private var calendar: Calendar { Calendar.current }

    private var leading: Int {
        (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
    }

    private var symbols: [String] {
        let all = calendar.shortStandaloneWeekdaySymbols
        let pivot = max(0, min(all.count, calendar.firstWeekday - 1))
        return Array(all[pivot...]) + Array(all[..<pivot])
    }

    private var dates: [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        return range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
    }

    private var events: [CalendarDate: LeaveCalendarDay] {
        Dictionary(days.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 4), count: 7) }

    var body: some View {
        let lookup = events
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, s in
                Text(s).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Palette.textTertiary).padding(4)
            }
            ForEach(0..<leading, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.row).fill(Palette.textPrimary.opacity(0.025)).frame(minHeight: 74).opacity(0.3)
            }
            ForEach(dates, id: \.self) { date in
                let day = CalendarDate(date)
                DayCell(date: day,
                        isWeekend: calendar.isDateInWeekend(date),
                        event: lookup[day],
                        showLeave: showLeave)
            }
        }
    }
}

private struct DayCell: View {
    let date: CalendarDate
    let isWeekend: Bool
    let event: LeaveCalendarDay?
    var showLeave = true

    private var isToday: Bool { date == CalendarDate(Date()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(date.day)").font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(isToday ? Palette.textPrimary : Palette.textTertiary)
            if let event, event.isHoliday, let name = event.holidayName { EventChip(text: name, kind: .holiday) }
            if showLeave, let event, event.isLeave {
                let pending = LeaveStatus(rawValue: event.leaveStatus ?? "")?.isPending == true
                EventChip(text: "You · \(event.isHalfDay ? "Half day" : (pending ? "Pending" : "Leave"))", kind: pending ? .pending : .me)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .background(Palette.textPrimary.opacity(isWeekend ? 0.01 : 0.025), in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).strokeBorder(isToday ? Palette.accent : Palette.hairline, lineWidth: isToday ? 2 : 1))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Holidays (prototype V.holidays: list 1 : calendar 1.4)

struct HolidaysView: View {
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var holidays: Loadable<[Holiday]> = .idle
    @State private var calendarModel: MonthCalendarModel
    @State private var actionError: AppError?
    @State private var actionMessage: String?
    @State private var working: UUID?
    private let leave: LeaveService

    init(environment: AppEnvironment) {
        leave = environment.leave
        _calendarModel = State(initialValue: MonthCalendarModel(environment: environment))
    }

    var body: some View {
        Page {
            FractionalColumns(ratio: 1 / 1.4) {
                Card("\(year.formatted(.number.grouping(.never))) holidays",
                     trailing: AnyView(HStack(spacing: 4) {
                         Button("‹") { year -= 1 }.buttonStyle(.effi)
                         Button("›") { year += 1 }.buttonStyle(.effi)
                     })) {
                    if let actionMessage { Text(actionMessage).font(Typo.caption).foregroundStyle(Palette.success) }
                    LoadStateView(state: holidays, emptyTitle: "No holidays", emptyMessage: "Your organisation hasn't published holidays for this year.",
                                  emptySymbol: "sun.max", isEmpty: { $0.isEmpty }, retry: { Task { await load() } }) { items in
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, h in
                                ListItemRow(title: h.name, subtitle: h.description, bold: true, showsDivider: index < items.count - 1) {
                                    DateBlock(date: h.date.date() ?? Date())
                                } trailing: {
                                    holidayTrailing(h)
                                }
                            }
                        }
                    }
                }
                LeaveCalendarCard(model: calendarModel, showLeave: false)
            }
        }
        .task(id: year) { await load() }
        .alert("Action failed", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } }),
               presenting: actionError) { _ in Button("OK", role: .cancel) {} } message: { Text($0.userMessage) }
    }

    @ViewBuilder
    private func holidayTrailing(_ h: Holiday) -> some View {
        if working == h.id {
            ProgressView().controlSize(.small)
        } else if h.userCompoffClaimed == true {
            Pill(text: "Comp-off claimed", kind: .vio)
        } else if h.userLeaveApplied == true {
            Pill(text: "Leave applied", kind: .blue)
        } else {
            HStack(spacing: 6) {
                Pill(text: h.date < CalendarDate(Date()) ? "Past" : "Holiday", kind: h.date < CalendarDate(Date()) ? .gray : .ok)
                Menu {
                    Button("Claim Comp-off (I worked this day)") { Task { await act(h, compOff: true) } }
                    Button("Apply Leave for This Holiday") { Task { await act(h, compOff: false) } }
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Holiday actions")
            }
        }
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

// MARK: - Leave balance (prototype V.balance; GET /leave/balance + /leave/policy/me)

struct LeaveBalanceView: View {
    @Environment(AppModel.self) private var model
    @State private var balance: Loadable<LeaveBalance> = .idle
    @State private var policy: EffectiveLeavePolicy?
    @State private var pending: [LeaveApplication] = []
    private let leave: LeaveService
    private let year = Calendar.current.component(.year, from: Date())

    init(environment: AppEnvironment) { leave = environment.leave }

    private struct Row: Identifiable {
        let id: String
        let color: Color
        let entitled: String
        let used: String
        let pending: String
        let available: String
        let utilisation: Double?
    }

    var body: some View {
        Page {
            Card(padding: 6) {
                LoadStateView(state: balance, retry: { Task { await load() } }) { b in
                    EffiTable<Row>(rows: rows(b), columns: [
                        .init("Leave type") { r in
                            HStack(spacing: 8) { Circle().fill(r.color).frame(width: 8, height: 8); Text(r.id).font(Typo.bodyEmphasis) }
                        },
                        .init("Entitled", width: 90) { r in Text(r.entitled).font(Typo.mono) },
                        .init("Used", width: 80) { r in Text(r.used).font(Typo.mono) },
                        .init("Pending", width: 80) { r in Text(r.pending).font(Typo.mono) },
                        .init("Available", width: 90) { r in Text(r.available).font(.system(size: 13, weight: .bold, design: .monospaced)) },
                        .init("Utilisation", width: 220) { r in
                            if let u = r.utilisation { ProgressBar(value: u, tint: r.color) } else { Text("—").foregroundStyle(Palette.textTertiary) }
                        },
                    ])
                }
            }
            EqualColumns(count: 2) {
                Card("This year") {
                    if let b = balance.value {
                        VStack(alignment: .leading, spacing: 8) {
                            SetRowLite("Total leave taken", "\(Format.days(b.totalLeaveTaken)) days")
                            SetRowLite("Carried forward", "\(Format.days(b.carryForward)) days")
                            if let h = b.holidaysInYear { SetRowLite("Holidays", "\(h)") }
                            if let reserved = b.holidayReserved { SetRowLite("Reserved for holidays", "\(Format.days(reserved)) days") }
                        }
                    } else {
                        Text("—").foregroundStyle(Palette.textTertiary)
                    }
                }
                Card("Policy notes") {
                    if let policy {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("• \(policy.paidLeaveDaysPerYear) paid leave days per year.")
                            if let carry = policy.carryForwardLimit { Text("• Up to \(carry) unused days carry forward.") }
                            if let limit = policy.monthlyLeaveLimit { Text("• At most \(Format.days(limit)) leave days per month.") }
                            Text("• \(Format.days(policy.weeklyRequiredHours)) hours required per week over \(policy.weeklyWorkingDays) working days.")
                            if policy.hasUserOverride || policy.hasGroupOverride { Text("• Includes a \(policy.hasUserOverride ? "personal" : "group") override.") }
                        }
                        .font(Typo.body).foregroundStyle(Palette.textSecondary).lineSpacing(5)
                    } else {
                        Text("Policy unavailable.").font(Typo.body).foregroundStyle(Palette.textTertiary)
                    }
                }
            }
        }
        .task { await load() }
    }

    private func rows(_ b: LeaveBalance) -> [Row] {
        let pendingDays = pending.reduce(Decimal(0)) { $0 + $1.durationDays.value }
        func ratio(_ used: FlexibleDecimal, _ total: FlexibleDecimal) -> Double? {
            total.doubleValue > 0 ? used.doubleValue / total.doubleValue : nil
        }
        return [
            Row(id: "Paid", color: Palette.accent, entitled: Format.days(b.paidAllocated), used: Format.days(b.paidUsed),
                pending: Format.days(FlexibleDecimal(pendingDays)), available: Format.days(b.paidRemaining), utilisation: ratio(b.paidUsed, b.paidAllocated)),
            Row(id: "Comp-off", color: Palette.okFill, entitled: Format.days(b.compOffBalance), used: Format.days(b.compOffUsed),
                pending: "—", available: Format.days(b.compOffRemaining), utilisation: ratio(b.compOffUsed, b.compOffBalance)),
            Row(id: "Unpaid", color: Palette.violetFill, entitled: "—", used: Format.days(b.unpaidUsed), pending: "—", available: "—", utilisation: nil),
        ]
    }

    private func load() async {
        balance = .loading
        do { balance = .loaded(try await leave.balance(year: year)) } catch { balance = .failed(DashboardViewModel.map(error)) }
        policy = try? await leave.myPolicy()
        pending = (try? await leave.applications(userId: model.user?.id, pageSize: 200).items.filter { $0.statusValue?.isPending == true }) ?? []
    }
}

/// Compact label/value row inside a card.
struct SetRowLite: View {
    let label: String
    let value: String
    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
    var body: some View {
        HStack {
            Text(label).font(Typo.body).foregroundStyle(Palette.textSecondary)
            Spacer()
            Text(value).font(Typo.mono)
        }
    }
}
