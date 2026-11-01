import Foundation

// Thin, typed façades over core-services endpoints. They contain no business
// rules — validation, balance computation, approval routing and permissions
// are enforced by the backend; the UI only reflects server responses.
// Every path below was verified against core-services/app/api/v1/*.py.

/// Date-range helper used by dashboard / analytics / task-time queries.
public struct DateRange: Sendable, Hashable {
    public var from: CalendarDate
    public var to: CalendarDate
    public init(from: CalendarDate, to: CalendarDate) {
        self.from = from
        self.to = to
    }

    public static func today(calendar: Calendar = .current, now: Date = Date()) -> DateRange {
        let day = CalendarDate(now, calendar: calendar)
        return DateRange(from: day, to: day)
    }

    /// Monday-start (or locale-start) week containing `now`.
    public static func thisWeek(calendar: Calendar = .current, now: Date = Date()) -> DateRange {
        let interval = calendar.dateInterval(of: .weekOfYear, for: now)
        let start = interval?.start ?? now
        let end = interval.flatMap { calendar.date(byAdding: .day, value: -1, to: $0.end) } ?? now
        return DateRange(from: CalendarDate(start, calendar: calendar), to: CalendarDate(end, calendar: calendar))
    }

    func apply(to query: inout [URLQueryItem]) {
        query.add("date_from", from)
        query.add("date_to", to)
    }
}

// MARK: - Profile & consent

public struct ProfileService: Sendable {
    let api: APIClient
    public init(api: APIClient) { self.api = api }

    /// `GET /users/me` → `UserOut`.
    public func me() async throws -> UserOut {
        try await api.send(Endpoint<UserOut>(.get, "/users/me"))
    }

    /// `GET /users/{id}` (manager / admin) → `UserDetail` incl. `last_device_seen`.
    public func user(_ id: UUID) async throws -> UserDetail {
        try await api.send(Endpoint<UserDetail>(.get, "/users/\(id.uuidString.lowercased())"))
    }

    /// `GET /users/profile` → `UserProfileOut` (manager name, leave summary).
    public func profile() async throws -> UserProfileOut {
        try await api.send(Endpoint<UserProfileOut>(.get, "/users/profile"))
    }

    /// `PATCH /users/me`.
    public func update(_ update: ProfileUpdate) async throws -> UserOut {
        try await api.send(.json(.patch, "/users/me", body: update))
    }

    /// `POST /auth/forgot-password` (no auth) — the server emails a reset link
    /// and answers the same way whether or not the address exists.
    public func forgotPassword(email: String) async throws -> MessageResponse {
        try await api.send(.json(.post, "/auth/forgot-password", body: ForgotPasswordRequest(email: email), auth: .none, idempotent: false))
    }

    /// `PATCH /auth/change-password` → new `TokenResponse`.
    public func changePassword(_ request: ChangePasswordRequest) async throws -> TokenResponse {
        try await api.send(.json(.patch, "/auth/change-password", body: request, idempotent: false))
    }
}

public struct ConsentService: Sendable {
    let api: APIClient
    public init(api: APIClient) { self.api = api }

    /// `GET /consent/status` (portal or agent token).
    public func status() async throws -> ConsentStatusResponse {
        try await api.send(Endpoint<ConsentStatusResponse>(.get, "/consent/status"))
    }

    /// `POST /consent/accept`.
    public func accept(policyVersion: Int) async throws -> ConsentAcceptResponse {
        try await api.send(.json(.post, "/consent/accept", body: ConsentAcceptRequest(policyVersion: policyVersion), idempotent: true))
    }
}

// MARK: - Agent (agent token)

public struct AgentAPIService: Sendable {
    let api: APIClient
    public init(api: APIClient) { self.api = api }

    /// `GET /agent/config` (sends `X-Timezone`).
    public func config() async throws -> AgentConfigResponse {
        try await api.send(Endpoint<AgentConfigResponse>(.get, "/agent/config", auth: .agent))
    }

    /// `GET /agent/time-stats?timezone=`.
    public func timeStats(timezone: TimeZone = .current) async throws -> AgentTimeStatsResponse {
        var query: [URLQueryItem] = []
        query.add("timezone", timezone.identifier)
        return try await api.send(Endpoint<AgentTimeStatsResponse>(.get, "/agent/time-stats", query: query, auth: .agent))
    }

    /// `GET /agent/version` (no auth).
    public func latestVersion() async throws -> AgentVersionResponse {
        try await api.send(Endpoint<AgentVersionResponse>(.get, "/agent/version", auth: .none))
    }
}

// MARK: - Projects & task time

public struct WorkService: Sendable {
    let api: APIClient
    public init(api: APIClient) { self.api = api }

    /// `GET /projects/assigned` → projects with their assigned tasks.
    public func assignedProjects() async throws -> [AssignedProject] {
        try await api.send(Endpoint<[AssignedProject]>(.get, "/projects/assigned"))
    }

    /// `GET /projects/{id}/tasks`.
    public func tasks(projectId: UUID) async throws -> PagedResponse<TaskOut> {
        try await api.send(Endpoint<PagedResponse<TaskOut>>(.get, "/projects/\(projectId.uuidString.lowercased())/tasks"))
    }

    /// `GET /task-time` — own logs unless `userId` given (manager/admin scope enforced server-side).
    public func timeLogs(range: DateRange, userId: UUID? = nil, page: Int = 1, pageSize: Int = 100) async throws -> TaskTimeLogListResponse {
        var query: [URLQueryItem] = []
        range.apply(to: &query)
        query.add("user_id", userId)
        query.add("timezone", TimeZone.current.identifier)
        query.add("page", page)
        query.add("page_size", pageSize)
        return try await api.send(Endpoint<TaskTimeLogListResponse>(.get, "/task-time", query: query))
    }

    /// `GET /task-time/summary`.
    public func taskSummary(range: DateRange, userId: UUID? = nil) async throws -> TaskTimeSummaryResponse {
        var query: [URLQueryItem] = []
        range.apply(to: &query)
        query.add("user_id", userId)
        query.add("timezone", TimeZone.current.identifier)
        return try await api.send(Endpoint<TaskTimeSummaryResponse>(.get, "/task-time/summary", query: query))
    }

    /// `GET /task-time/project-summary`.
    public func projectSummary(range: DateRange, userId: UUID? = nil) async throws -> ProjectTimeSummaryResponse {
        var query: [URLQueryItem] = []
        range.apply(to: &query)
        query.add("user_id", userId)
        query.add("timezone", TimeZone.current.identifier)
        return try await api.send(Endpoint<ProjectTimeSummaryResponse>(.get, "/task-time/project-summary", query: query))
    }

    /// `POST /task-time/manual` — admin/super_admin only (backend returns 403 otherwise).
    public func createManualLog(_ body: ManualTimeLogCreate) async throws -> ManualTimeLogOut {
        try await api.send(.json(.post, "/task-time/manual", body: body, idempotent: false))
    }
}

// MARK: - Dashboard & analytics

public struct InsightsService: Sendable {
    let api: APIClient
    public init(api: APIClient) { self.api = api }

    private func rangedQuery(_ range: DateRange, userId: UUID?) -> [URLQueryItem] {
        var query: [URLQueryItem] = []
        range.apply(to: &query)
        query.add("user_id", userId)
        query.add("timezone", TimeZone.current.identifier)
        return query
    }

    /// `GET /dashboard/individual`.
    public func individualDashboard(range: DateRange, userId: UUID? = nil) async throws -> IndividualDashboardResponse {
        try await api.send(Endpoint<IndividualDashboardResponse>(.get, "/dashboard/individual", query: rangedQuery(range, userId: userId)))
    }

    /// `GET /dashboard/team` (manager+).
    public func teamDashboard(range: DateRange) async throws -> TeamDashboardResponse {
        try await api.send(Endpoint<TeamDashboardResponse>(.get, "/dashboard/team", query: rangedQuery(range, userId: nil)))
    }

    /// `GET /analytics/utilisation`.
    public func utilisation(range: DateRange, userId: UUID? = nil) async throws -> UtilisationResponse {
        try await api.send(Endpoint<UtilisationResponse>(.get, "/analytics/utilisation", query: rangedQuery(range, userId: userId)))
    }

    /// `GET /analytics/productivity-score`.
    public func productivity(range: DateRange, userId: UUID? = nil) async throws -> ProductivityScoreResponse {
        try await api.send(Endpoint<ProductivityScoreResponse>(.get, "/analytics/productivity-score", query: rangedQuery(range, userId: userId)))
    }

    /// `GET /analytics/timeline` — synced activity events (app, domain, idle…).
    public func timeline(range: DateRange, userId: UUID? = nil, page: Int = 1, pageSize: Int = 200) async throws -> TimelineResponse {
        var query = rangedQuery(range, userId: userId)
        query.add("page", page)
        query.add("page_size", pageSize)
        return try await api.send(Endpoint<TimelineResponse>(.get, "/analytics/timeline", query: query))
    }

    /// `GET /analytics/app-usage`.
    public func appUsage(range: DateRange, userId: UUID? = nil, pageSize: Int = 20) async throws -> AppUsageResponse {
        var query = rangedQuery(range, userId: userId)
        query.add("page_size", pageSize)
        return try await api.send(Endpoint<AppUsageResponse>(.get, "/analytics/app-usage", query: query))
    }

    /// `GET /analytics/domain-usage`.
    public func domainUsage(range: DateRange, userId: UUID? = nil, pageSize: Int = 20) async throws -> DomainUsageResponse {
        var query = rangedQuery(range, userId: userId)
        query.add("page_size", pageSize)
        return try await api.send(Endpoint<DomainUsageResponse>(.get, "/analytics/domain-usage", query: query))
    }
}

// MARK: - Notifications

public struct NotificationService: Sendable {
    let api: APIClient
    public init(api: APIClient) { self.api = api }

    /// `GET /notifications?skip&limit&unread_only`.
    public func list(skip: Int = 0, limit: Int = 50, unreadOnly: Bool = false) async throws -> NotificationListResponse {
        var query: [URLQueryItem] = []
        query.add("skip", skip)
        query.add("limit", limit)
        query.add("unread_only", unreadOnly)
        return try await api.send(Endpoint<NotificationListResponse>(.get, "/notifications", query: query))
    }

    /// `GET /notifications/unread-count`.
    public func unreadCount() async throws -> Int {
        try await api.send(Endpoint<UnreadCountResponse>(.get, "/notifications/unread-count")).count
    }

    /// `PATCH /notifications/{id}/read`.
    public func markRead(_ id: UUID) async throws -> NotificationItem {
        try await api.send(Endpoint<NotificationItem>(.patch, "/notifications/\(id.uuidString.lowercased())/read", idempotent: true))
    }

    /// `POST /notifications/mark-all-read`.
    public func markAllRead() async throws -> Int {
        try await api.send(Endpoint<MarkAllReadResponse>(.post, "/notifications/mark-all-read", idempotent: true)).updated
    }
}
