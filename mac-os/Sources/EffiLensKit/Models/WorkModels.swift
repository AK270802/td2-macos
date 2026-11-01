import Foundation

// Projects, tasks and task-time. Mirrors core-services/app/schemas/project.py,
// schemas/task_time.py and the response models declared in api/v1/task_time.py.

/// `AssignedTaskOut` (project schema) nested in `AssignedProjectOut`.
public struct AssignedTask: Decodable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let name: String
    public let description: String?
}

/// `AssignedProjectOut` — `GET /projects/assigned` (portal or agent).
public struct AssignedProject: Decodable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let name: String
    public let description: String?
    public let tasks: [AssignedTask]
}

/// `ProjectOut` — `GET /projects`.
public struct ProjectOut: Decodable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let name: String
    public let description: String?
    public let archived: Bool
    public let createdAt: Date
    public let assignmentType: String?
    public let taskCount: Int?
}

/// `TaskOut` — `GET /projects/{id}/tasks`.
/// Note: the backend has no priority / due date / estimate fields; the
/// prototype's task metadata is therefore not shown (see API_INTEGRATION.md).
public struct TaskOut: Decodable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let projectId: UUID
    public let name: String
    public let description: String?
    public let assignmentType: String?
    public let assigneeIds: [UUID]?
    public let createdAt: Date
}

/// `TaskTimeLogOut` — items of `GET /task-time`.
public struct TaskTimeLog: Decodable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let taskId: UUID?
    public let projectId: UUID?
    public let taskName: String
    public let projectName: String
    public let userId: UUID
    public let displayName: String?
    public let startedAt: Date
    public let endedAt: Date
    public let durationSec: Int
    public let breakSec: Int?
    public let meetingSec: Int?
    public let isManual: Bool
    public let isBreak: Bool?
    public let isBreakPaid: Bool?
    public let createdById: UUID?
}

/// `TaskTimeLogListResponse`.
public typealias TaskTimeLogListResponse = PagedResponse<TaskTimeLog>

/// `TaskTimeSummaryItem`.
public struct TaskTimeSummaryItem: Decodable, Sendable, Hashable {
    public let taskId: UUID?
    public let taskName: String?
    public let projectId: UUID?
    public let projectName: String?
    public let totalDurationSec: Int
    public let totalMeetingSec: Int?
    public let logCount: Int?
}

/// `TaskTimeSummaryResponse` — `GET /task-time/summary`.
public struct TaskTimeSummaryResponse: Decodable, Sendable {
    public let items: [TaskTimeSummaryItem]
    public let totalDurationSec: Int
}

/// `ProjectTimeSummaryItem`.
public struct ProjectTimeSummaryItem: Decodable, Sendable, Hashable {
    public let projectId: UUID?
    public let projectName: String?
    public let totalDurationSec: Int
    public let totalMeetingSec: Int?
    public let logCount: Int?
    public let taskCount: Int?
}

/// `ProjectTimeSummaryResponse` — `GET /task-time/project-summary`.
public struct ProjectTimeSummaryResponse: Decodable, Sendable {
    public let items: [ProjectTimeSummaryItem]
    public let totalDurationSec: Int
}

/// `ManualTimeLogCreate` — `POST /task-time/manual` (admin/super_admin only;
/// managers and employees receive 403 — verified in api/v1/task_time.py).
public struct ManualTimeLogCreate: Encodable, Sendable {
    public let userId: UUID
    public let taskId: UUID
    public let projectId: UUID?
    public let startedAt: Date
    public let endedAt: Date
    public let timezone: String?

    public init(userId: UUID, taskId: UUID, projectId: UUID?, startedAt: Date, endedAt: Date, timezone: String?) {
        self.userId = userId
        self.taskId = taskId
        self.projectId = projectId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.timezone = timezone
    }
}

/// `ManualTimeLogOut`.
public struct ManualTimeLogOut: Decodable, Sendable, Identifiable {
    public let id: UUID
    public let userId: UUID
    public let taskId: UUID
    public let taskName: String?
    public let projectId: UUID
    public let projectName: String?
    public let startedAt: Date
    public let endedAt: Date
    public let durationSec: Int
    public let tzOffset: Int
    public let isManual: Bool
    public let createdById: UUID?
}
