import Foundation

// Mirrors core-services/app/schemas/leave.py and app/models/leave.py.
// The leave type of an application is DERIVED by the backend (paid vs unpaid
// depending on balance) — `LeaveApplicationCreate` has no type field. The
// client never computes balances; it displays the server's computed fields.

/// `ApplicationStatus` enum (app/models/leave.py).
public enum LeaveStatus: String, Codable, Sendable, CaseIterable {
    case pendingManager = "pending_manager"
    case pendingAdmin = "pending_admin"
    case approved
    case rejected
    case cancelled

    public var displayName: String {
        switch self {
        case .pendingManager: return "Awaiting manager"
        case .pendingAdmin: return "Awaiting admin"
        case .approved: return "Approved"
        case .rejected: return "Rejected"
        case .cancelled: return "Cancelled"
        }
    }

    public var isPending: Bool { self == .pendingManager || self == .pendingAdmin }
}

/// `LeaveType` enum (app/models/leave.py).
public enum LeaveKind: String, Codable, Sendable, CaseIterable {
    case paid, unpaid, pending, mixed, holiday, compensatory

    public var displayName: String {
        switch self {
        case .paid: return "Paid"
        case .unpaid: return "Unpaid"
        case .pending: return "At approval"
        case .mixed: return "Paid + Unpaid"
        case .holiday: return "Holiday"
        case .compensatory: return "Comp-off"
        }
    }
}

/// `LeaveSource` enum.
public enum LeaveSource: String, Codable, Sendable {
    case manual
    case automatedDeficit = "automated_deficit"
    case holidayCompoff = "holiday_compoff"

    public var displayName: String {
        switch self {
        case .manual: return "Manual"
        case .automatedDeficit: return "Automatic"
        case .holidayCompoff: return "Comp-off"
        }
    }
}

/// `LeaveBalanceOut` — `GET /leave/balance?user_id&year`.
public struct LeaveBalance: Decodable, Sendable, Equatable {
    public let userId: UUID
    public let year: Int
    public let paidAllocated: FlexibleDecimal
    public let paidUsed: FlexibleDecimal
    public let unpaidUsed: FlexibleDecimal
    public let compOffBalance: FlexibleDecimal
    public let compOffUsed: FlexibleDecimal
    public let carryForward: FlexibleDecimal
    public let holidayReserved: FlexibleDecimal?
    public let holidaysInYear: Int?
    // Server @computed_field values — never recomputed client-side.
    public let totalLeaveTaken: FlexibleDecimal?
    public let paidRemaining: FlexibleDecimal?
    public let compOffRemaining: FlexibleDecimal?
}

/// `LeaveApplicationOut`.
public struct LeaveApplication: Decodable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let tenantId: UUID
    public let userId: UUID
    public let startDate: CalendarDate
    public let endDate: CalendarDate
    public let durationDays: FlexibleDecimal
    public let paidDays: FlexibleDecimal?
    public let unpaidDays: FlexibleDecimal?
    public let leaveType: String
    public let source: String
    public let reason: String?
    public let status: String
    public let managerApprovedBy: UUID?
    public let managerApprovedAt: Date?
    public let managerRejectionReason: String?
    public let managerRejectedBy: UUID?
    public let managerRejectedAt: Date?
    public let adminApprovedBy: UUID?
    public let adminApprovedAt: Date?
    public let adminRejectionReason: String?
    public let adminRejectedBy: UUID?
    public let adminRejectedAt: Date?
    public let createdByRole: String
    public let createdById: UUID?
    public let createdAt: Date
    public let updatedAt: Date
    public let userDisplayName: String?
    public let userRole: String?
    public let userEmail: String?
    /// Optional advisory message from the server (e.g. "counted as unpaid").
    public let message: String?

    public var statusValue: LeaveStatus? { LeaveStatus(rawValue: status) }
    public var kind: LeaveKind? { LeaveKind(rawValue: leaveType) }
    public var sourceValue: LeaveSource? { LeaveSource(rawValue: source) }

    /// The rejection reason from whichever stage rejected the request.
    public var rejectionReason: String? { adminRejectionReason ?? managerRejectionReason }

    /// Employees may withdraw while pending. The backend remains the
    /// authority — a 4xx from DELETE is surfaced verbatim.
    public var isWithdrawable: Bool { statusValue?.isPending == true }
}

/// `LeaveApplicationListResponse`.
public typealias LeaveApplicationListResponse = PagedResponse<LeaveApplication>

/// `LeaveApplicationCreate` — `POST /leave/applications`.
public struct LeaveApplicationCreate: Encodable, Sendable {
    /// Only managers/admins may apply on behalf of someone else.
    public var userId: UUID?
    public var startDate: CalendarDate
    public var endDate: CalendarDate
    public var halfDay: Bool
    public var reason: String?

    public init(userId: UUID? = nil, startDate: CalendarDate, endDate: CalendarDate, halfDay: Bool, reason: String?) {
        self.userId = userId
        self.startDate = startDate
        self.endDate = endDate
        self.halfDay = halfDay
        self.reason = reason
    }
}

/// `LeaveApplicationUpdate` — `PATCH /leave/applications/{id}`.
public struct LeaveApplicationUpdate: Encodable, Sendable {
    public var startDate: CalendarDate?
    public var endDate: CalendarDate?
    public var halfDay: Bool?
    public var reason: String?
    /// Optimistic concurrency token — send the `updated_at` you loaded.
    public var clientUpdatedAt: Date?

    public init(startDate: CalendarDate? = nil, endDate: CalendarDate? = nil, halfDay: Bool? = nil, reason: String? = nil, clientUpdatedAt: Date? = nil) {
        self.startDate = startDate
        self.endDate = endDate
        self.halfDay = halfDay
        self.reason = reason
        self.clientUpdatedAt = clientUpdatedAt
    }
}

/// `ManagerApprovePayload`.
public struct LeaveApprovePayload: Encodable, Sendable {
    public var clientUpdatedAt: Date?
    public init(clientUpdatedAt: Date?) { self.clientUpdatedAt = clientUpdatedAt }
}

/// `LeaveRejectPayload`.
public struct LeaveRejectPayload: Encodable, Sendable {
    public var rejectionReason: String
    public init(rejectionReason: String) { self.rejectionReason = rejectionReason }
}

/// `BulkLeaveActionPayload` / `BulkLeaveRejectPayload`.
public struct BulkLeaveActionPayload: Encodable, Sendable {
    public var applicationIds: [UUID]
    public init(applicationIds: [UUID]) { self.applicationIds = applicationIds }
}

public struct BulkLeaveRejectPayload: Encodable, Sendable {
    public var applicationIds: [UUID]
    public var rejectionReason: String
    public init(applicationIds: [UUID], rejectionReason: String) {
        self.applicationIds = applicationIds
        self.rejectionReason = rejectionReason
    }
}

/// `BulkLeaveActionResponse`.
public struct BulkLeaveActionResponse: Decodable, Sendable {
    public struct Failure: Decodable, Sendable, Hashable {
        public let applicationId: UUID
        public let error: String
    }
    public let succeeded: [UUID]
    public let failed: [Failure]
    public let total: Int
    public let succeededCount: Int
    public let failedCount: Int
}

/// `HolidayOut` — `GET /leave/holidays?year`.
public struct Holiday: Decodable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let tenantId: UUID
    public let date: CalendarDate
    public let name: String
    public let description: String?
    public let createdBy: UUID?
    public let createdAt: Date
    public let leaveApplied: Bool?
    public let compoffClaimed: Bool?
    public let userCompoffClaimed: Bool?
    public let userLeaveApplied: Bool?
}

/// `HolidayCreate` (admin).
public struct HolidayCreate: Encodable, Sendable {
    public var date: CalendarDate
    public var name: String
    public var description: String?
    public init(date: CalendarDate, name: String, description: String?) {
        self.date = date
        self.name = name
        self.description = description
    }
}

/// `HolidayCompOffClaimCreate` / `HolidayLeaveApplyCreate`.
public struct HolidayActionPayload: Encodable, Sendable {
    public var holidayId: UUID?
    public var reason: String?
    public init(holidayId: UUID?, reason: String?) {
        self.holidayId = holidayId
        self.reason = reason
    }
}

/// `CalendarDay`.
public struct LeaveCalendarDay: Decodable, Sendable, Hashable {
    public let date: CalendarDate
    public let isWeekend: Bool
    public let isHoliday: Bool
    public let holidayName: String?
    public let isLeave: Bool
    public let isHalfDay: Bool
    public let leaveType: String?
    public let leaveStatus: String?
}

/// `LeaveCalendarOut` — `GET /leave/calendar?year&month&user_id`.
public struct LeaveCalendar: Decodable, Sendable {
    public let year: Int
    public let month: Int
    public let monthLeaveCount: FlexibleDecimal
    public let holidayCount: Int
    public let days: [LeaveCalendarDay]
}

/// `EffectivePolicyOut` — `GET /leave/policy/me`.
public struct EffectiveLeavePolicy: Decodable, Sendable, Equatable {
    public let evaluationPeriod: String
    public let timezone: String?
    public let dailyMinHours: FlexibleDecimal
    public let dailyMaxHours: FlexibleDecimal
    public let weeklyRequiredHours: FlexibleDecimal
    public let weeklyWorkingDays: Int
    public let monthlyRequiredHours: FlexibleDecimal
    public let monthlyWorkingDays: Int
    public let paidLeaveDaysPerYear: Int
    public let monthlyLeaveLimit: FlexibleDecimal?
    public let carryForwardLimit: Int?
    public let hasUserOverride: Bool
    public let hasGroupOverride: Bool
}

/// `LeavePolicyOut` / `LeavePolicyUpsert` — `GET|PUT /leave/policy` (admin).
public struct LeavePolicy: Codable, Sendable, Equatable {
    public var evaluationPeriod: String
    public var timezone: String
    public var dailyMinHours: FlexibleDecimal
    public var dailyMaxHours: FlexibleDecimal
    public var weeklyRequiredHours: FlexibleDecimal
    public var weeklyWorkingDays: Int
    public var monthlyRequiredHours: FlexibleDecimal
    public var monthlyWorkingDays: Int
    public var paidLeaveDaysPerYear: Int
    public var monthlyLeaveLimit: FlexibleDecimal?
    public var carryForwardLimit: Int?
}
