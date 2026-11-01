import Foundation
import Observation
import EffiLensKit

/// Dashboard data. Each card loads independently so one failing endpoint
/// never blanks the whole screen. All figures come from the backend.
@MainActor
@Observable
final class DashboardViewModel {
    struct WeekSummary: Equatable {
        let workedSec: Int
        /// From the effective leave/working-hours policy (`weekly_required_hours`).
        let requiredSec: Int?
    }

    private(set) var today: Loadable<SummaryCard> = .idle
    private(set) var week: Loadable<WeekSummary> = .idle
    private(set) var weeklyActivity: Loadable<[UtilisationDay]> = .idle
    private(set) var recentSessions: Loadable<[TaskTimeLog]> = .idle
    private(set) var balance: Loadable<LeaveBalance> = .idle
    private(set) var pendingLeaveCount: Int?
    private(set) var upcoming: Loadable<[UpcomingItem]> = .idle

    struct UpcomingItem: Identifiable, Equatable {
        enum Kind: Equatable { case holiday, leave(LeaveStatus?) }
        let id: UUID
        let date: CalendarDate
        let endDate: CalendarDate?
        let title: String
        let kind: Kind
    }

    private let insights: InsightsService
    private let work: WorkService
    private let leave: LeaveService
    private let calendar = Calendar.current

    init(environment: AppEnvironment) {
        insights = environment.insights
        work = environment.work
        leave = environment.leave
    }

    func load() async {
        async let a: Void = loadToday()
        async let b: Void = loadWeek()
        async let c: Void = loadWeeklyActivity()
        async let d: Void = loadRecentSessions()
        async let e: Void = loadLeave()
        _ = await (a, b, c, d, e)
    }

    func loadToday() async {
        today = .loading
        do {
            today = .loaded(try await insights.individualDashboard(range: .today()).summary)
        } catch { today = .failed(Self.map(error)) }
    }

    func loadWeek() async {
        week = .loading
        let insights = self.insights, leave = self.leave
        do {
            async let dashboard = insights.individualDashboard(range: .thisWeek())
            async let policy = try? leave.myPolicy()
            let worked = try await dashboard.summary.workedSec
            let required = await policy.map { Int(($0.weeklyRequiredHours.doubleValue * 3600).rounded()) }
            week = .loaded(WeekSummary(workedSec: worked, requiredSec: required.flatMap { $0 > 0 ? $0 : nil }))
        } catch { week = .failed(Self.map(error)) }
    }

    func loadWeeklyActivity() async {
        weeklyActivity = .loading
        do {
            weeklyActivity = .loaded(try await insights.utilisation(range: .thisWeek()).days)
        } catch { weeklyActivity = .failed(Self.map(error)) }
    }

    func loadRecentSessions() async {
        recentSessions = .loading
        let end = CalendarDate(Date(), calendar: calendar)
        let start = CalendarDate(calendar.date(byAdding: .day, value: -6, to: Date()) ?? Date(), calendar: calendar)
        do {
            let logs = try await work.timeLogs(range: DateRange(from: start, to: end), pageSize: 20).items
            recentSessions = .loaded(Array(logs.filter { $0.isBreak != true }.sorted { $0.startedAt > $1.startedAt }.prefix(5)))
        } catch { recentSessions = .failed(Self.map(error)) }
    }

    func loadLeave() async {
        balance = .loading
        upcoming = .loading
        let year = calendar.component(.year, from: Date())
        let todayDate = CalendarDate(Date(), calendar: calendar)
        let leave = self.leave

        async let balanceResult = Result(asyncCatching: { try await leave.balance(year: year) })
        async let holidaysResult = Result(asyncCatching: { try await leave.holidays(year: year) })
        async let applicationsResult = Result(asyncCatching: { try await leave.applications(startFrom: todayDate, pageSize: 20) })

        switch await balanceResult {
        case .success(let value): balance = .loaded(value)
        case .failure(let error): balance = .failed(Self.map(error))
        }

        let holidays = await holidaysResult
        let applications = await applicationsResult
        if case .success(let list) = applications {
            pendingLeaveCount = list.items.filter { $0.statusValue?.isPending == true }.count
        }
        switch (holidays, applications) {
        case (.failure(let error), _), (_, .failure(let error)):
            upcoming = .failed(Self.map(error))
        case (.success(let holidayList), .success(let applicationList)):
            let holidayItems = holidayList
                .filter { $0.date >= todayDate }
                .map { UpcomingItem(id: $0.id, date: $0.date, endDate: nil, title: $0.name, kind: .holiday) }
            let leaveItems = applicationList.items
                .filter { $0.statusValue != .cancelled && $0.statusValue != .rejected }
                .map { UpcomingItem(id: $0.id, date: $0.startDate, endDate: $0.endDate, title: $0.kind?.displayName ?? "Leave", kind: .leave($0.statusValue)) }
            upcoming = .loaded(Array((holidayItems + leaveItems).sorted { $0.date < $1.date }.prefix(4)))
        }
    }

    static func map(_ error: Error) -> AppError {
        (error as? AppError) ?? .unknown(String(describing: type(of: error)))
    }
}

private extension Result where Failure == Error {
    init(asyncCatching body: () async throws -> Success) async {
        do { self = .success(try await body()) } catch { self = .failure(error) }
    }
}
