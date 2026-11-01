import Foundation

// Dashboard, analytics and notifications. Mirrors core-services
// schemas/dashboard.py, schemas/analytics.py and api/v1/notifications.py.

/// `SummaryCard`.
public struct SummaryCard: Decodable, Sendable, Equatable {
    public let totalTimeSec: Int
    public let workedSec: Int
    public let taskLoggedSec: Int
    public let productiveSec: Int
    public let unproductiveSec: Int
    public let idleSec: Int
    public let breakSec: Int
    public let meetingSec: Int
    public let utilisationPct: Int
    public let productivePct: Int
    public let unproductivePct: Int
    public let idlePct: Int
    public let activeUsers: Int

    enum CodingKeys: String, CodingKey {
        case totalTimeSec, workedSec, taskLoggedSec, productiveSec, unproductiveSec, idleSec,
             breakSec, meetingSec, utilisationPct, productivePct, unproductivePct, idlePct, activeUsers
    }

    // Every SummaryCard field has a server default of 0; decode leniently.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func int(_ key: CodingKeys) -> Int { (try? c.decodeIfPresent(Int.self, forKey: key)) ?? 0 }
        totalTimeSec = int(.totalTimeSec)
        workedSec = int(.workedSec)
        taskLoggedSec = int(.taskLoggedSec)
        productiveSec = int(.productiveSec)
        unproductiveSec = int(.unproductiveSec)
        idleSec = int(.idleSec)
        breakSec = int(.breakSec)
        meetingSec = int(.meetingSec)
        utilisationPct = int(.utilisationPct)
        productivePct = int(.productivePct)
        unproductivePct = int(.unproductivePct)
        idlePct = int(.idlePct)
        activeUsers = int(.activeUsers)
    }
}

/// `ProjectTimeItem`.
public struct ProjectTimeItem: Decodable, Sendable, Hashable, Identifiable {
    public let projectId: UUID
    public let projectName: String
    public let totalSec: Int
    public let color: String?
    public var id: UUID { projectId }
}

/// `AppUsageItem` (dashboard variant: `total_sec`, category productive|non_productive|unrated).
public struct DashboardAppUsage: Decodable, Sendable, Hashable {
    public let appName: String
    public let totalSec: Int
    public let category: String
}

/// `TimelineSegment`.
public struct TimelineSegment: Decodable, Sendable, Hashable, Identifiable {
    public let taskLogId: UUID
    public let taskId: UUID?
    public let taskName: String
    public let projectName: String
    public let startedAt: Date
    public let endedAt: Date
    public let durationSec: Int
    public let idleSec: Int?
    public let breakSec: Int?
    public let meetingSec: Int?
    public let isManual: Bool?
    public var id: UUID { taskLogId }
}

/// `UserTimeItem` (team dashboard).
public struct UserTimeItem: Decodable, Sendable, Hashable, Identifiable {
    public let userId: UUID
    public let displayName: String
    public let email: String
    public let totalSec: Int
    public let workedSec: Int?
    public let meetingSec: Int?
    public let productivePct: Int
    public let idlePct: Int
    public let utilisationPct: Int?
    public let activityLevel: String
    public var id: UUID { userId }
}

/// `IndividualDashboardResponse` — `GET /dashboard/individual` (min role user).
public struct IndividualDashboardResponse: Decodable, Sendable {
    public let summary: SummaryCard
    public let timeline: [TimelineSegment]
    public let topProductiveApps: [DashboardAppUsage]
    public let topUnproductiveApps: [DashboardAppUsage]
    public let topProjects: [ProjectTimeItem]
    public let activityLevel: String?

    enum CodingKeys: String, CodingKey {
        case summary, timeline, topProductiveApps, topUnproductiveApps, topProjects, activityLevel
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary = try c.decode(SummaryCard.self, forKey: .summary)
        timeline = try c.decodeIfPresent([TimelineSegment].self, forKey: .timeline) ?? []
        topProductiveApps = try c.decodeIfPresent([DashboardAppUsage].self, forKey: .topProductiveApps) ?? []
        topUnproductiveApps = try c.decodeIfPresent([DashboardAppUsage].self, forKey: .topUnproductiveApps) ?? []
        topProjects = try c.decodeIfPresent([ProjectTimeItem].self, forKey: .topProjects) ?? []
        activityLevel = try c.decodeIfPresent(String.self, forKey: .activityLevel)
    }
}

/// `TeamDashboardResponse` — `GET /dashboard/team` (min role manager).
public struct TeamDashboardResponse: Decodable, Sendable {
    public let summary: SummaryCard
    public let topProjects: [ProjectTimeItem]
    public let usersNotTracking: [UserTimeItem]
    public let mostHoursUsers: [UserTimeItem]

    enum CodingKeys: String, CodingKey { case summary, topProjects, usersNotTracking, mostHoursUsers }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary = try c.decode(SummaryCard.self, forKey: .summary)
        topProjects = try c.decodeIfPresent([ProjectTimeItem].self, forKey: .topProjects) ?? []
        usersNotTracking = try c.decodeIfPresent([UserTimeItem].self, forKey: .usersNotTracking) ?? []
        mostHoursUsers = try c.decodeIfPresent([UserTimeItem].self, forKey: .mostHoursUsers) ?? []
    }
}

/// `UtilisationDay` / `UtilisationResponse` — `GET /analytics/utilisation`.
public struct UtilisationDay: Decodable, Sendable, Hashable {
    public let date: CalendarDate
    public let activeSec: Int
    public let idleSec: Int
    public let breakSec: Int
    public let utilisationPct: Double
}

public struct UtilisationResponse: Decodable, Sendable {
    public let days: [UtilisationDay]
    public let avgUtilisationPct: Double
}

/// `ProductivityScoreDay` / `ProductivityScoreResponse` — `GET /analytics/productivity-score`.
public struct ProductivityScoreDay: Decodable, Sendable, Hashable {
    public let date: CalendarDate
    public let score: Double
    public let band: String
    public let productiveSec: Int
    public let totalTrackedSec: Int
}

public struct ProductivityScoreResponse: Decodable, Sendable {
    public let days: [ProductivityScoreDay]
    public let avgScore: Double
}

/// `AppUsageItem` / `AppUsageResponse` (analytics variant: `duration_sec`, `percentage`).
public struct AppUsageItem: Decodable, Sendable, Hashable {
    public let appName: String
    public let durationSec: Int
    public let category: String
    public let percentage: Double
}

public struct AppUsageResponse: Decodable, Sendable {
    public let items: [AppUsageItem]
    public let totalSec: Int
    public let total: Int
}

/// `DomainUsageItem` / `DomainUsageResponse`.
public struct DomainUsageItem: Decodable, Sendable, Hashable {
    public let domain: String
    public let faviconUrl: String?
    public let visitCount: Int
    public let totalSec: Int
    public let category: String
    public let percentage: Double
}

public struct DomainUsageResponse: Decodable, Sendable {
    public let items: [DomainUsageItem]
    public let totalSec: Int
    public let total: Int
}

/// `NotificationOut` — `GET /notifications`.
public struct NotificationItem: Decodable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let type: String
    public let title: String
    public let message: String
    public let entityType: String?
    public let entityId: UUID?
    public let isRead: Bool
    public let createdAt: Date
    public let actorId: UUID?
}

/// `NotificationListResponse`.
public struct NotificationListResponse: Decodable, Sendable {
    public let items: [NotificationItem]
    public let total: Int
    public let unreadCount: Int
}

/// `UnreadCountResponse`.
public struct UnreadCountResponse: Decodable, Sendable {
    public let count: Int
}

/// `MarkAllReadResponse`.
public struct MarkAllReadResponse: Decodable, Sendable {
    public let updated: Int
}
