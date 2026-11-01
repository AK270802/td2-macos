import Foundation

// Mirrors core-services/app/schemas/user.py.

/// Backend role strings (`ROLE_HIERARCHY` in app/core/rbac.py).
public enum UserRole: String, Codable, Sendable, Comparable, CaseIterable {
    case user, manager, admin
    case superAdmin = "super_admin"

    public var rank: Int {
        switch self {
        case .user: return 1
        case .manager: return 2
        case .admin: return 3
        case .superAdmin: return 4
        }
    }

    public static func < (lhs: UserRole, rhs: UserRole) -> Bool { lhs.rank < rhs.rank }

    /// Mirrors `require_minimum_role` semantics.
    public func atLeast(_ minimum: UserRole) -> Bool { rank >= minimum.rank }

    public var displayName: String {
        switch self {
        case .user: return "Employee"
        case .manager: return "Manager"
        case .admin: return "Administrator"
        case .superAdmin: return "Super Admin"
        }
    }
}

/// `UserOut` — `GET /users/me`.
public struct UserOut: Decodable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let email: String
    public let displayName: String
    /// Raw role string; use `roleValue` for typed checks.
    public let role: String
    public let consentStatus: String
    public let isActive: Bool
    public let timezone: String
    public let organizationName: String?
    public let createdAt: Date
    public let contactNo: String?
    public let joiningDate: CalendarDate?
    public let country: String?
    public let employmentType: String?

    /// Unknown future roles degrade to least privilege.
    public var roleValue: UserRole { UserRole(rawValue: role) ?? .user }

    public var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? String(email.prefix(1)).uppercased() : letters.uppercased()
    }
}

/// `LeaveSection` nested in `UserProfileOut`.
public struct ProfileLeaveSection: Decodable, Sendable, Equatable {
    public let annualLeaves: FlexibleDecimal?
    public let carryForward: FlexibleDecimal?
    public let totalLeaves: FlexibleDecimal?
    public let totalLeavesUsed: FlexibleDecimal?
    public let unpaidLeaves: FlexibleDecimal?
    public let workingDays: Int?
}

/// `UserProfileOut` — `GET /users/profile`.
public struct UserProfileOut: Decodable, Sendable, Equatable {
    public let id: UUID
    public let tenantId: UUID
    public let email: String
    public let fullName: String?
    public let role: String
    public let isActive: Bool
    public let managerId: UUID?
    public let managerName: String?
    public let joiningDate: CalendarDate?
    public let country: String?
    public let employmentType: String?
    public let leave: ProfileLeaveSection
}

/// `ProfileUpdate` — `PATCH /users/me` (subset the app edits).
public struct ProfileUpdate: Encodable, Sendable {
    public var displayName: String?
    public var timezone: String?
    public init(displayName: String? = nil, timezone: String? = nil) {
        self.displayName = displayName
        self.timezone = timezone
    }
}

/// Generic paginated list used by several endpoints (`items/total/page/page_size`).
public struct PagedResponse<Item: Decodable & Sendable>: Decodable, Sendable {
    public let items: [Item]
    public let total: Int
    public let page: Int?
    public let pageSize: Int?
}

/// `UserOut` list — `GET /users` (manager/admin; used for team screens).
public typealias UserListResponse = PagedResponse<UserOut>
