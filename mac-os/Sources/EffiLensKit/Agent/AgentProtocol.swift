import Foundation

// Wire types for the local IPC protocol shared with the Rust agent
// (`common::ipc_transport`, `agentd/src/ipc.rs`): newline-delimited JSON
// `{cmd, payload?, auth}` → `{ok, data, error}`.
//
// `auth` is the per-boot IPC secret added for the native macOS daemon (see
// RUST_AGENT_INTEGRATION.md §Socket authentication). The legacy Tauri agent
// ignores unknown fields, so the request shape stays backward compatible.

public enum AgentPaths {
    /// `~/Library/Application Support/EffiLens/` — distinct from the legacy
    /// Tauri agent's `~/Library/Application Support/WorkPulseAgentRust/`.
    public static func supportDirectory(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return base.appending(path: "EffiLens", directoryHint: .isDirectory)
    }

    /// Unix domain socket the native agent listens on (0600, owner-only).
    public static func socketURL() throws -> URL {
        try supportDirectory().appending(path: "agent.sock", directoryHint: .notDirectory)
    }

    /// Per-boot random secret written by the agent (0600). Clients must present it.
    public static func ipcTokenURL() throws -> URL {
        try supportDirectory().appending(path: "ipc.token", directoryHint: .notDirectory)
    }

    /// Legacy Tauri agent socket (`$TMPDIR/workpulse-agent.sock`). Only probed,
    /// never written to — used to detect a running legacy agent.
    public static var legacySocketURL: URL {
        FileManager.default.temporaryDirectory.appending(path: "workpulse-agent.sock", directoryHint: .notDirectory)
    }
}

/// Commands understood by the agent. String values are load-bearing and
/// match `handle_request` in agentd/src/ipc.rs, plus `set_session` /
/// `clear_session` / `get_permissions` added for the native daemon.
public enum AgentCommand: String, Sendable {
    case ping
    case getState = "get_state"
    case togglePlayPause = "toggle_play_pause"
    case selectTask = "select_task"
    case startBreak = "start_break"
    case stopTracking = "stop_tracking"
    case idleKeepWorking = "idle_keep_working"
    case idleAutoStop = "idle_auto_stop"
    case getAssignedTasks = "get_assigned_tasks"
    case getTimeStats = "get_time_stats"
    case getTaskTimesToday = "get_task_times_today"
    case getRecentEvents = "get_recent_events"
    case getSyncStatus = "get_sync_status"
    case syncNow = "sync_now"
    case clearLocalData = "clear_local_data"
    // Native-daemon additions (Milestone 3).
    case setSession = "set_session"
    case clearSession = "clear_session"
    case getPermissions = "get_permissions"
    case requestPermissions = "request_permissions"
    case getAgentToken = "get_agent_token"
}

struct AgentRequest<Payload: Encodable>: Encodable {
    let cmd: String
    let payload: Payload?
    let auth: String
}

struct AgentResponse<DataType: Decodable>: Decodable {
    let ok: Bool
    let data: DataType?
    let error: String?
}

/// Task reference used in `select_task` and returned in `get_state`.
public struct AgentTaskRef: Codable, Sendable, Hashable {
    public let taskId: String
    public let projectId: String
    public let taskName: String
    public let projectName: String

    public init(taskId: String, projectId: String, taskName: String, projectName: String) {
        self.taskId = taskId
        self.projectId = projectId
        self.taskName = taskName
        self.projectName = projectName
    }
}

/// `get_state` response (agentd/src/ipc.rs).
public struct AgentTimerState: Decodable, Sendable, Equatable {
    public enum Phase: String, Decodable, Sendable {
        case idle, running, paused
        case onBreak = "on_break"
    }

    public let state: Phase
    public let task: AgentTaskRef?
    public let elapsedSecs: Int
    public let breakType: String?
    public let breakRemainingSecs: Int?
    public let idleWarning: Bool
    public let idleSinceSecs: Int?
    public let inMeeting: Bool

    public static let stopped = AgentTimerState(
        state: .idle, task: nil, elapsedSecs: 0, breakType: nil,
        breakRemainingSecs: nil, idleWarning: false, idleSinceSecs: nil, inMeeting: false
    )

    public init(state: Phase, task: AgentTaskRef?, elapsedSecs: Int, breakType: String?, breakRemainingSecs: Int?, idleWarning: Bool, idleSinceSecs: Int?, inMeeting: Bool) {
        self.state = state
        self.task = task
        self.elapsedSecs = elapsedSecs
        self.breakType = breakType
        self.breakRemainingSecs = breakRemainingSecs
        self.idleWarning = idleWarning
        self.idleSinceSecs = idleSinceSecs
        self.inMeeting = inMeeting
    }

    enum CodingKeys: String, CodingKey {
        case state, task, elapsedSecs, breakType, breakRemainingSecs, idleWarning, idleSinceSecs, inMeeting
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = try c.decode(Phase.self, forKey: .state)
        task = try c.decodeIfPresent(AgentTaskRef.self, forKey: .task)
        elapsedSecs = try c.decodeIfPresent(Int.self, forKey: .elapsedSecs) ?? 0
        breakType = try c.decodeIfPresent(String.self, forKey: .breakType)
        breakRemainingSecs = try c.decodeIfPresent(Int.self, forKey: .breakRemainingSecs)
        idleWarning = try c.decodeIfPresent(Bool.self, forKey: .idleWarning) ?? false
        idleSinceSecs = try c.decodeIfPresent(Int.self, forKey: .idleSinceSecs)
        inMeeting = try c.decodeIfPresent(Bool.self, forKey: .inMeeting) ?? false
    }
}

/// `get_sync_status` response (`SyncStatus` in agentd/src/sync_loop.rs).
/// Timestamps are Unix seconds (`Option<i64>` in Rust), not ISO strings.
public struct AgentSyncStatus: Decodable, Sendable, Equatable {
    public let connected: Bool
    public let lastSyncTs: Int64?
    public let lastResult: String?
    public let pendingEvents: Int
    public let nextSyncTs: Int64?
    public let agentVersion: String?

    public var lastSync: Date? { lastSyncTs.map { Date(timeIntervalSince1970: TimeInterval($0)) } }
    public var nextSync: Date? { nextSyncTs.map { Date(timeIntervalSince1970: TimeInterval($0)) } }
}

/// `get_time_stats` response.
public struct AgentLocalTimeStats: Decodable, Sendable, Equatable {
    public let workedTodaySec: Int
    public let workedWeekSec: Int
    public let workedMonthSec: Int
    public let sessionsToday: Int
    public let meetingTodaySec: Int
}

/// `get_permissions` response (native daemon).
public struct AgentPermissions: Decodable, Sendable, Equatable {
    public let accessibility: Bool
    public let screenRecording: Bool
    public let inputMonitoring: Bool
}

/// `get_agent_token` response — the daemon's current agent token.
public struct AgentTokenInfo: Decodable, Sendable, Equatable {
    public let token: String
    public let userId: String
}

/// `set_session` payload — hands the agent token to the daemon.
public struct AgentSessionPayload: Encodable, Sendable {
    public let accessToken: String
    public let userId: String
    public let tenantId: String
    public let apiBaseUrl: String

    public init(accessToken: String, userId: String, tenantId: String, apiBaseUrl: String) {
        self.accessToken = accessToken
        self.userId = userId
        self.tenantId = tenantId
        self.apiBaseUrl = apiBaseUrl
    }
}

/// `start_break` payload.
public struct AgentBreakPayload: Encodable, Sendable {
    public let breakType: String
    public let durationSecs: Int
    public init(breakType: String, durationSecs: Int) {
        self.breakType = breakType
        self.durationSecs = durationSecs
    }
}

/// One locally recorded activity event (`common::models::ActivityEvent`),
/// reduced to the fields the Activity timeline shows. `payload` (app names,
/// window titles, domains) is intentionally not decoded.
public struct AgentRecentEvent: Decodable, Sendable, Hashable, Identifiable {
    public let eventUuid: UUID
    public let eventType: String
    public let ts: Int64
    public let durationSec: Int64

    public var id: UUID { eventUuid }
    public var date: Date { Date(timeIntervalSince1970: TimeInterval(ts)) }

    public init(eventUuid: UUID, eventType: String, ts: Int64, durationSec: Int64) {
        self.eventUuid = eventUuid
        self.eventType = eventType
        self.ts = ts
        self.durationSec = durationSec
    }
}
