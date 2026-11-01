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

/// Leave Overview — prototype `V.leave`: hero "Time off, simplified.";
/// 4 ring cards; Pending & recent (1 fr) + Upcoming holidays (1 fr).
/// Categories are the backend's real ones (paid / comp-off / unpaid /
/// carry-forward); the prototype's Annual/Sick split is not supported by
/// core-services and is not faked (gap B8).
struct LeaveOverviewView: View {
    @Environment(Navigator.self) private var navigator
    @State private var viewModel: LeaveOverviewViewModel
    let onNavigate: (Route) -> Void

    init(environment: AppEnvironment, onNavigate: @escaping (Route) -> Void) {
        _viewModel = State(initialValue: LeaveOverviewViewModel(environment: environment))
        self.onNavigate = onNavigate
    }

    var body: some View {
        Page {
            HeroTitle(prefix: "Time ", emphasis: "off", suffix: ", simplified.").padding(.bottom, 4)
            LoadStateView(state: viewModel.balance, retry: { Task { await viewModel.loadBalance() } }) { b in
                EqualColumns(count: 4) {
                    ringCard("Paid Leave", remaining: b.paidRemaining, total: b.paidAllocated, used: b.paidUsed, tint: Palette.accent)
                    ringCard("Comp-off", remaining: b.compOffRemaining, total: b.compOffBalance, used: b.compOffUsed, tint: Palette.okFill)
                    valueCard("Unpaid Leave", value: b.unpaidUsed, caption: "days taken this year", tint: Palette.violetFill)
                    valueCard("Carry Forward", value: b.carryForward, caption: "days from last year", tint: Palette.blueFill)
                }
            }
            EqualColumns(count: 2) {
                recentCard
                holidaysCard
            }
        }
        .task { await viewModel.load() }
        .alert("Couldn't withdraw request",
               isPresented: Binding(get: { viewModel.actionError != nil }, set: { if !$0 { viewModel.actionError = nil } }),
               presenting: viewModel.actionError) { _ in Button("OK", role: .cancel) {} } message: { Text($0.userMessage) }
    }

    private func ringCard(_ title: String, remaining: FlexibleDecimal?, total: FlexibleDecimal, used: FlexibleDecimal, tint: Color) -> some View {
        Card {
            VStack(spacing: 0) {
                ProgressRing(progress: total.doubleValue > 0 ? (remaining?.doubleValue ?? 0) / total.doubleValue : 0, lineWidth: 8, tint: tint) {
                    VStack(spacing: 0) {
                        Text(Format.days(remaining)).font(.system(size: 22, weight: .semibold, design: .monospaced))
                        Text("left").font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                    }
                }
                .frame(width: 96, height: 96)
                Text(title).font(Typo.bodyEmphasis).padding(.top, 10)
                Text("\(Format.days(used)) used of \(Format.days(total))").font(Typo.caption).foregroundStyle(Palette.textTertiary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func valueCard(_ title: String, value: FlexibleDecimal, caption: String, tint: Color) -> some View {
        Card {
            VStack(spacing: 0) {
                ZStack {
                    Circle().stroke(tint.opacity(0.25), lineWidth: 8)
                    Text(Format.days(value)).font(.system(size: 22, weight: .semibold, design: .monospaced))
                }
                .frame(width: 96, height: 96)
                Text(title).font(Typo.bodyEmphasis).padding(.top, 10)
                Text(caption).font(Typo.caption).foregroundStyle(Palette.textTertiary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var recentCard: some View {
        Card("Pending & recent", trailing: AnyView(CardLink("All requests") { onNavigate(.myRequests) })) {
            LoadStateView(state: viewModel.recent, emptyTitle: "No leave requests yet", emptySymbol: "tray",
                          isEmpty: { $0.isEmpty }, retry: { Task { await viewModel.loadRecent() } }) { items in
                let shown = Array(items.prefix(3))
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, a in
                        Button {
                            navigator.leaveDetail = LeaveDetailContext(application: a, mode: .own, back: .leaveOverview)
                        } label: {
                            ListItemRow(title: "\(a.kind?.displayName ?? "Leave") · \(Format.days(a.durationDays)) day\(a.durationDays.doubleValue == 1 ? "" : "s")",
                                        subtitle: Format.dateRange(a.startDate, a.endDate), bold: true, showsDivider: index < shown.count - 1) {
                                IconTile(symbol: "leaf", tint: Palette.accent)
                            } trailing: {
                                LeaveStatusPill(status: a.statusValue)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var holidaysCard: some View {
        Card("Upcoming holidays", trailing: AnyView(CardLink("Calendar") { onNavigate(.holidays) })) {
            LoadStateView(state: viewModel.holidays, emptyTitle: "No upcoming holidays", emptySymbol: "sun.max",
                          isEmpty: { $0.isEmpty }, retry: { Task { await viewModel.loadHolidays() } }) { items in
                let shown = Array(items.prefix(4))
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, h in
                        ListItemRow(title: h.name, subtitle: h.date.date()?.formatted(.dateTime.weekday(.wide).day().month(.wide)) ?? h.date.description,
                                    bold: true, showsDivider: index < shown.count - 1) {
                            IconTile(symbol: "sun.max", tint: Palette.okFill)
                        } trailing: {
                            Pill(text: "Holiday", kind: .ok)
                        }
                    }
                }
            }
        }
    }
}
