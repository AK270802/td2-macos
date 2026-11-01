import Foundation

/// Façade over `/api/v1/leave/*` (core-services/app/api/v1/leave.py).
///
/// Approval routing (pending_manager → pending_admin → approved), paid/unpaid
/// classification, holiday exclusion and balance arithmetic all happen on the
/// server. Role gates noted per call mirror the backend dependencies; the UI
/// hides actions the role cannot perform, and the server remains authoritative.
public struct LeaveService: Sendable {
    let api: APIClient
    public init(api: APIClient) { self.api = api }

    private static func idPath(_ id: UUID) -> String { id.uuidString.lowercased() }

    // MARK: Balance, policy, calendar (any signed-in user)

    /// `GET /leave/balance?user_id&year`.
    public func balance(userId: UUID? = nil, year: Int? = nil) async throws -> LeaveBalance {
        var query: [URLQueryItem] = []
        query.add("user_id", userId)
        query.add("year", year)
        return try await api.send(Endpoint<LeaveBalance>(.get, "/leave/balance", query: query))
    }

    /// `GET /leave/policy/me`.
    public func myPolicy() async throws -> EffectiveLeavePolicy {
        try await api.send(Endpoint<EffectiveLeavePolicy>(.get, "/leave/policy/me"))
    }

    /// `GET /leave/calendar?year&month&user_id`.
    public func calendar(year: Int, month: Int, userId: UUID? = nil) async throws -> LeaveCalendar {
        var query: [URLQueryItem] = []
        query.add("year", year)
        query.add("month", month)
        query.add("user_id", userId)
        return try await api.send(Endpoint<LeaveCalendar>(.get, "/leave/calendar", query: query))
    }

    /// `GET /leave/holidays?year&user_id`.
    public func holidays(year: Int? = nil, userId: UUID? = nil) async throws -> [Holiday] {
        var query: [URLQueryItem] = []
        query.add("year", year)
        query.add("user_id", userId)
        return try await api.send(Endpoint<[Holiday]>(.get, "/leave/holidays", query: query))
    }

    // MARK: Applications

    /// `GET /leave/applications` — scope (own / team / tenant) is decided by the server from the role.
    public func applications(
        userId: UUID? = nil,
        status: LeaveStatus? = nil,
        startFrom: CalendarDate? = nil,
        startTo: CalendarDate? = nil,
        page: Int = 1,
        pageSize: Int = 50
    ) async throws -> LeaveApplicationListResponse {
        var query: [URLQueryItem] = []
        query.add("user_id", userId)
        query.add("status", status?.rawValue)
        query.add("start_from", startFrom)
        query.add("start_to", startTo)
        query.add("page", page)
        query.add("page_size", pageSize)
        return try await api.send(Endpoint<LeaveApplicationListResponse>(.get, "/leave/applications", query: query))
    }

    /// `GET /leave/applications/{id}`.
    public func application(_ id: UUID) async throws -> LeaveApplication {
        try await api.send(Endpoint<LeaveApplication>(.get, "/leave/applications/\(Self.idPath(id))"))
    }

    /// `POST /leave/applications`.
    public func apply(_ body: LeaveApplicationCreate) async throws -> LeaveApplication {
        try await api.send(.json(.post, "/leave/applications", body: body, idempotent: false))
    }

    /// `PATCH /leave/applications/{id}`.
    public func update(_ id: UUID, _ body: LeaveApplicationUpdate) async throws -> LeaveApplication {
        try await api.send(.json(.patch, "/leave/applications/\(Self.idPath(id))", body: body, idempotent: false))
    }

    /// `DELETE /leave/applications/{id}` — cancels; returns the cancelled application.
    public func cancel(_ id: UUID) async throws -> LeaveApplication {
        try await api.send(Endpoint<LeaveApplication>(.delete, "/leave/applications/\(Self.idPath(id))", idempotent: false))
    }

    // MARK: Approvals

    /// `POST /leave/applications/{id}/manager-approve` (manager+).
    public func managerApprove(_ application: LeaveApplication) async throws -> LeaveApplication {
        try await api.send(.json(.post, "/leave/applications/\(Self.idPath(application.id))/manager-approve",
                                 body: LeaveApprovePayload(clientUpdatedAt: application.updatedAt), idempotent: false))
    }

    /// `POST /leave/applications/{id}/manager-reject` (manager+).
    public func managerReject(_ id: UUID, reason: String) async throws -> LeaveApplication {
        try await api.send(.json(.post, "/leave/applications/\(Self.idPath(id))/manager-reject",
                                 body: LeaveRejectPayload(rejectionReason: reason), idempotent: false))
    }

    /// `POST /leave/applications/{id}/admin-approve` (admin+).
    public func adminApprove(_ id: UUID) async throws -> LeaveApplication {
        try await api.send(Endpoint<LeaveApplication>(.post, "/leave/applications/\(Self.idPath(id))/admin-approve", idempotent: false))
    }

    /// `POST /leave/applications/{id}/admin-reject` (admin+).
    public func adminReject(_ id: UUID, reason: String) async throws -> LeaveApplication {
        try await api.send(.json(.post, "/leave/applications/\(Self.idPath(id))/admin-reject",
                                 body: LeaveRejectPayload(rejectionReason: reason), idempotent: false))
    }

    /// `POST /leave/applications/bulk-approve` (manager+).
    public func bulkApprove(_ ids: [UUID]) async throws -> BulkLeaveActionResponse {
        try await api.send(.json(.post, "/leave/applications/bulk-approve", body: BulkLeaveActionPayload(applicationIds: ids), idempotent: false))
    }

    /// `POST /leave/applications/bulk-reject` (manager+).
    public func bulkReject(_ ids: [UUID], reason: String) async throws -> BulkLeaveActionResponse {
        try await api.send(.json(.post, "/leave/applications/bulk-reject",
                                 body: BulkLeaveRejectPayload(applicationIds: ids, rejectionReason: reason), idempotent: false))
    }

    // MARK: Holidays

    /// `POST /leave/holidays/{id}/claim-compoff`.
    public func claimCompOff(holidayId: UUID, reason: String?) async throws -> LeaveApplication {
        try await api.send(.json(.post, "/leave/holidays/\(Self.idPath(holidayId))/claim-compoff",
                                 body: HolidayActionPayload(holidayId: holidayId, reason: reason), idempotent: false))
    }

    /// `POST /leave/holidays/{id}/apply-leave`.
    public func applyHolidayLeave(holidayId: UUID, reason: String?) async throws -> LeaveApplication {
        try await api.send(.json(.post, "/leave/holidays/\(Self.idPath(holidayId))/apply-leave",
                                 body: HolidayActionPayload(holidayId: holidayId, reason: reason), idempotent: false))
    }

    /// `POST /leave/holidays` (admin).
    public func createHoliday(_ body: HolidayCreate) async throws -> Holiday {
        try await api.send(.json(.post, "/leave/holidays", body: body, idempotent: false))
    }

    /// `DELETE /leave/holidays/{id}` (admin).
    public func deleteHoliday(_ id: UUID) async throws {
        _ = try await api.send(Endpoint<EmptyResponse>(.delete, "/leave/holidays/\(Self.idPath(id))"))
    }

    // MARK: Admin policy

    /// `GET /leave/policy` (admin).
    public func tenantPolicy() async throws -> LeavePolicy {
        try await api.send(Endpoint<LeavePolicy>(.get, "/leave/policy"))
    }

    /// `PUT /leave/policy` (admin).
    public func updateTenantPolicy(_ policy: LeavePolicy) async throws -> LeavePolicy {
        try await api.send(.json(.put, "/leave/policy", body: policy))
    }

    /// `GET /leave/balance/all?year` (admin) — organisation-wide report.
    public func allBalances(year: Int) async throws -> [LeaveBalance] {
        var query: [URLQueryItem] = []
        query.add("year", year)
        return try await api.send(Endpoint<[LeaveBalance]>(.get, "/leave/balance/all", query: query))
    }
}
