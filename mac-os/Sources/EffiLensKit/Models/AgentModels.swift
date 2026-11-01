import Foundation

// Mirrors core-services/app/schemas/agent.py and schemas/consent.py.

/// `AssignedTaskOut` (agent schema).
public struct AgentAssignedTask: Decodable, Sendable, Hashable, Identifiable {
    public let taskId: UUID
    public let projectId: UUID
    public let taskName: String
    public let projectName: String
    public var id: UUID { taskId }
}

/// `AgentConfigResponse` — `GET /agent/config` (agent token).
public struct AgentConfigResponse: Decodable, Sendable, Equatable {
    public let userId: UUID
    public let tenantId: UUID
    public let idleThresholdSec: Int
    public let activityIdleThresholdSec: Int
    public let screenshotIntervalSec: Int
    public let screenshotsEnabled: Bool
    public let blurRadius: Int
    public let captureIntervalSec: Int
    public let batchSyncIntervalMin: Int
    public let assignmentSyncIntervalMin: Int
    public let breaksArePaid: Bool
    public let retentionDays: Int
    public let agentAutostart: Bool
    public let assignedTasks: [AgentAssignedTask]
    public let generalActivityTaskId: UUID?

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.userId == rhs.userId && lhs.screenshotIntervalSec == rhs.screenshotIntervalSec
            && lhs.idleThresholdSec == rhs.idleThresholdSec && lhs.assignedTasks == rhs.assignedTasks
            && lhs.screenshotsEnabled == rhs.screenshotsEnabled && lhs.blurRadius == rhs.blurRadius
    }
}

/// `TaskTimeStatsItem`.
public struct TaskTimeStatsItem: Decodable, Sendable, Hashable {
    public let taskId: UUID
    public let projectId: UUID
    public let taskName: String
    public let projectName: String
    public let durationSec: Int
}

/// `AgentTimeStatsResponse` — `GET /agent/time-stats?timezone=` (agent token).
public struct AgentTimeStatsResponse: Decodable, Sendable {
    public let todayLoggedSec: Int
    public let weekLoggedSec: Int
    public let monthLoggedSec: Int
    public let tasksToday: [TaskTimeStatsItem]
}

/// `AgentVersionResponse` — `GET /agent/version` (no auth).
public struct AgentVersionResponse: Decodable, Sendable {
    public let version: String
    public let downloadUrl: String
    public let sha256: String
    public let minSupportedVersion: String
}

/// `ConsentStatusResponse` — `GET /consent/status` (portal or agent).
public struct ConsentStatusResponse: Decodable, Sendable, Equatable {
    public let status: String?
    public let policyVersion: Int?
    public let policyContent: String?

    /// Backend values (`users.consent_status`, services/consent_service.py):
    /// "accepted" | "pending" | "withdrawn". Anything else fails closed.
    public var isAccepted: Bool { status == "accepted" }
}

/// `ConsentAcceptRequest` (extra='forbid' — send only this field).
public struct ConsentAcceptRequest: Encodable, Sendable {
    public let policyVersion: Int
    public init(policyVersion: Int) { self.policyVersion = policyVersion }
}

/// `ConsentAcceptResponse`.
public struct ConsentAcceptResponse: Decodable, Sendable {
    public let status: String
    public let acceptedAt: Date
}
