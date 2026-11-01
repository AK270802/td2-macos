import SwiftUI
import Observation
import EffiLensKit

@MainActor
@Observable
final class LeaveOverviewViewModel {
    private(set) var balance: Loadable<LeaveBalance> = .idle
    private(set) var recent: Loadable<[LeaveApplication]> = .idle
    private(set) var holidays: Loadable<[Holiday]> = .idle
    private(set) var withdrawing: Set<UUID> = []
    var actionError: AppError?

    private let leave: LeaveService
    private let year = Calendar.current.component(.year, from: Date())

    init(environment: AppEnvironment) {
        leave = environment.leave
    }

    func load() async {
        async let a: Void = loadBalance()
        async let b: Void = loadRecent()
        async let c: Void = loadHolidays()
        _ = await (a, b, c)
    }

    func loadBalance() async {
        balance = .loading
        do { balance = .loaded(try await leave.balance(year: year)) } catch { balance = .failed(DashboardViewModel.map(error)) }
    }

    func loadRecent() async {
        recent = .loading
        do {
            // Own applications (server scopes by role; employees only ever see their own).
            let page = try await leave.applications(pageSize: 10)
            recent = .loaded(page.items.sorted { $0.createdAt > $1.createdAt })
        } catch { recent = .failed(DashboardViewModel.map(error)) }
    }

    func loadHolidays() async {
        holidays = .loading
        let today = CalendarDate(Date())
        do {
            holidays = .loaded(try await leave.holidays(year: year).filter { $0.date >= today }.sorted { $0.date < $1.date })
        } catch { holidays = .failed(DashboardViewModel.map(error)) }
    }

    func withdraw(_ application: LeaveApplication) async {
        withdrawing.insert(application.id)
        defer { withdrawing.remove(application.id) }
        do {
            _ = try await leave.cancel(application.id)
            await loadRecent()
            await loadBalance()
        } catch {
            actionError = DashboardViewModel.map(error)
        }
    }
}

/// Leave Overview — prototype layout: balance rings, pending & recent
/// requests, upcoming holidays. Leave types are the backend's fixed set
/// (paid / unpaid / comp-off); the prototype's Annual/Sick/Casual split is
/// not supported by core-services and is not faked.
struct LeaveOverviewView: View {
    @State private var viewModel: LeaveOverviewViewModel
    @State private var pendingWithdrawal: LeaveApplication?
    let onNavigate: (Route) -> Void

    init(environment: AppEnvironment, onNavigate: @escaping (Route) -> Void) {
        _viewModel = State(initialValue: LeaveOverviewViewModel(environment: environment))
        self.onNavigate = onNavigate
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                balanceSection
                HStack(alignment: .top, spacing: Space.l) {
                    recentSection
                    holidaySection.frame(maxWidth: 360)
                }
            }
            .padding(Space.xl)
            .frame(maxWidth: 1240, alignment: .leading)
        }
        .task { await viewModel.load() }
        .confirmationDialog(
            "Withdraw this leave request?",
            isPresented: Binding(get: { pendingWithdrawal != nil }, set: { if !$0 { pendingWithdrawal = nil } }),
            presenting: pendingWithdrawal
        ) { application in
            Button("Withdraw Request", role: .destructive) { Task { await viewModel.withdraw(application) } }
        } message: { application in
            Text("\(Format.dateRange(application.startDate, application.endDate)) · \(Format.days(application.durationDays)) day(s). Your approver will be notified.")
        }
        .alert(
            "Couldn't withdraw request",
            isPresented: Binding(get: { viewModel.actionError != nil }, set: { if !$0 { viewModel.actionError = nil } }),
            presenting: viewModel.actionError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.userMessage)
        }
    }

    private var balanceSection: some View {
        Card("Balance \(Calendar.current.component(.year, from: Date()).formatted(.number.grouping(.never)))",
             trailing: AnyView(Button("Apply for Leave") { onNavigate(.applyLeave) }.buttonStyle(.borderedProminent))) {
            LoadStateView(state: viewModel.balance, retry: { Task { await viewModel.loadBalance() } }) { balance in
                HStack(alignment: .top, spacing: Space.xxl) {
                    LargeBalanceRing(title: "Paid leave", remaining: balance.paidRemaining, total: balance.paidAllocated,
                                     detail: "\(Format.days(balance.paidUsed)) used of \(Format.days(balance.paidAllocated))")
                    LargeBalanceRing(title: "Comp-off", remaining: balance.compOffRemaining, total: balance.compOffBalance,
                                     detail: "\(Format.days(balance.compOffUsed)) used of \(Format.days(balance.compOffBalance))")
                    VStack(alignment: .leading, spacing: Space.m) {
                        metric("Carried forward", "\(Format.days(balance.carryForward)) d")
                        metric("Unpaid taken", "\(Format.days(balance.unpaidUsed)) d")
                        if let reserved = balance.holidayReserved, reserved.doubleValue > 0 {
                            metric("Reserved for holidays", "\(Format.days(reserved)) d")
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text(label).font(Typo.caption).foregroundStyle(Palette.textSecondary)
            Text(value).font(Typo.heading).monospacedDigit()
        }
    }

    private var recentSection: some View {
        Card("Pending & recent", trailing: AnyView(Button("My Requests") { onNavigate(.myRequests) }.buttonStyle(.link))) {
            LoadStateView(
                state: viewModel.recent,
                emptyTitle: "No leave requests yet",
                emptyMessage: "Requests you submit will appear here with their approval status.",
                emptySymbol: "tray",
                isEmpty: { $0.isEmpty },
                retry: { Task { await viewModel.loadRecent() } }
            ) { applications in
                VStack(spacing: 0) {
                    ForEach(applications) { application in
                        LeaveApplicationRow(
                            application: application,
                            isWithdrawing: viewModel.withdrawing.contains(application.id),
                            onWithdraw: { pendingWithdrawal = application }
                        )
                        if application.id != applications.last?.id { Divider().overlay(Palette.hairline) }
                    }
                }
            }
        }
    }

    private var holidaySection: some View {
        Card("Upcoming holidays", trailing: AnyView(Button("All") { onNavigate(.holidays) }.buttonStyle(.link))) {
            LoadStateView(
                state: viewModel.holidays,
                emptyTitle: "No upcoming holidays",
                emptySymbol: "sun.max",
                isEmpty: { $0.isEmpty },
                retry: { Task { await viewModel.loadHolidays() } }
            ) { holidays in
                VStack(spacing: Space.s) {
                    ForEach(holidays.prefix(6)) { holiday in
                        HStack(spacing: Space.m) {
                            DateBlock(date: holiday.date)
                            VStack(alignment: .leading, spacing: Space.xxs) {
                                Text(holiday.name).font(Typo.bodyEmphasis).lineLimit(1)
                                if let description = holiday.description, !description.isEmpty {
                                    Text(description).font(Typo.caption).foregroundStyle(Palette.textSecondary).lineLimit(1)
                                }
                            }
                            Spacer()
                            if holiday.userCompoffClaimed == true { StatusPill(text: "Comp-off claimed", tone: .info) }
                            else if holiday.userLeaveApplied == true { StatusPill(text: "Leave applied", tone: .info) }
                        }
                    }
                }
            }
        }
    }
}

struct LeaveApplicationRow: View {
    let application: LeaveApplication
    let isWithdrawing: Bool
    let onWithdraw: () -> Void

    var body: some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                HStack(spacing: Space.s) {
                    Text(application.kind?.displayName ?? application.leaveType.capitalized).font(Typo.bodyEmphasis)
                    Text("· \(Format.days(application.durationDays)) d").font(Typo.body).foregroundStyle(Palette.textSecondary)
                }
                Text(Format.dateRange(application.startDate, application.endDate))
                    .font(Typo.caption).foregroundStyle(Palette.textSecondary)
                if let reason = application.rejectionReason, application.statusValue == .rejected {
                    Text("Reason: \(reason)").font(Typo.caption).foregroundStyle(Palette.danger).lineLimit(2)
                }
            }
            Spacer()
            LeaveStatusPill(status: application.statusValue)
            if application.isWithdrawable {
                if isWithdrawing {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Withdraw", action: onWithdraw).controlSize(.small)
                }
            }
        }
        .padding(.vertical, Space.s)
    }
}

struct LargeBalanceRing: View {
    let title: String
    let remaining: FlexibleDecimal?
    let total: FlexibleDecimal
    let detail: String

    private var progress: Double {
        guard let remaining, total.doubleValue > 0 else { return 0 }
        return remaining.doubleValue / total.doubleValue
    }

    var body: some View {
        VStack(spacing: Space.s) {
            ProgressRing(progress: progress, lineWidth: 9) {
                VStack(spacing: 0) {
                    Text(Format.days(remaining)).font(.system(size: 24, weight: .semibold, design: .monospaced))
                    Text("left").font(Typo.caption).foregroundStyle(Palette.textSecondary)
                }
            }
            .frame(width: 104, height: 104)
            Text(title).font(Typo.bodyEmphasis)
            Text(detail).font(Typo.caption).foregroundStyle(Palette.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(Format.days(remaining)) days left. \(detail).")
    }
}
