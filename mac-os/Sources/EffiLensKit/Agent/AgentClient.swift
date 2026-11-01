import Foundation
import Network

/// Client for the native EffiLens Rust agent over an authenticated Unix
/// domain socket. One connection per request (mirrors the Rust client in
/// `common::ipc_transport`), with a hard timeout so UI never hangs.
public actor AgentClient {
    public struct Options: Sendable {
        public var socketURL: URL
        public var tokenURL: URL
        public var timeout: Duration
        public init(socketURL: URL, tokenURL: URL, timeout: Duration = .seconds(3)) {
            self.socketURL = socketURL
            self.tokenURL = tokenURL
            self.timeout = timeout
        }

        public static func standard() throws -> Options {
            Options(socketURL: try AgentPaths.socketURL(), tokenURL: try AgentPaths.ipcTokenURL())
        }
    }

    private let options: Options
    private let queue = DispatchQueue(label: "com.baseel.effilens.agent-ipc")
    private static let maxResponseBytes = 4 * 1024 * 1024

    public init(options: Options) {
        self.options = options
    }

    // MARK: - Typed commands

    public func ping() async -> Bool {
        (try? await call(.ping, payload: Optional<String>.none, as: String.self)) == "pong"
    }

    public func state() async throws -> AgentTimerState {
        try await call(.getState, payload: Optional<String>.none, as: AgentTimerState.self)
    }

    public func syncStatus() async throws -> AgentSyncStatus {
        try await call(.getSyncStatus, payload: Optional<String>.none, as: AgentSyncStatus.self)
    }

    public func localTimeStats() async throws -> AgentLocalTimeStats {
        try await call(.getTimeStats, payload: Optional<String>.none, as: AgentLocalTimeStats.self)
    }

    public func permissions() async throws -> AgentPermissions {
        try await call(.getPermissions, payload: Optional<String>.none, as: AgentPermissions.self)
    }

    public func selectTask(_ task: AgentTaskRef) async throws {
        _ = try await call(.selectTask, payload: task, as: IgnoredValue.self)
    }

    public func togglePlayPause() async throws {
        _ = try await call(.togglePlayPause, payload: Optional<String>.none, as: IgnoredValue.self)
    }

    public func stopTracking() async throws {
        _ = try await call(.stopTracking, payload: Optional<String>.none, as: IgnoredValue.self)
    }

    public func startBreak(_ payload: AgentBreakPayload) async throws {
        _ = try await call(.startBreak, payload: payload, as: IgnoredValue.self)
    }

    public func resolveIdle(keepWorking: Bool) async throws {
        _ = try await call(keepWorking ? .idleKeepWorking : .idleAutoStop, payload: Optional<String>.none, as: IgnoredValue.self)
    }

    public func syncNow() async throws {
        _ = try await call(.syncNow, payload: Optional<String>.none, as: IgnoredValue.self)
    }

    public func setSession(_ payload: AgentSessionPayload) async throws {
        _ = try await call(.setSession, payload: payload, as: IgnoredValue.self)
    }

    public func clearSession() async throws {
        _ = try await call(.clearSession, payload: Optional<String>.none, as: IgnoredValue.self)
    }

    // MARK: - Transport

    /// Accepts any JSON value (including null) for commands whose data is unused.
    struct IgnoredValue: Decodable, Sendable {
        init(from decoder: Decoder) throws {}
    }

    func call<P: Encodable & Sendable, R: Decodable & Sendable>(_ command: AgentCommand, payload: P?, as type: R.Type) async throws -> R {
        let token = try readIPCToken()
        let encoder = JSONCoding.makeEncoder()
        var line = try encoder.encode(AgentRequest(cmd: command.rawValue, payload: payload, auth: token))
        line.append(0x0A)

        let responseData = try await exchange(line)
        let decoder = JSONCoding.makeDecoder()
        let envelope: AgentResponse<R>
        do {
            envelope = try decoder.decode(AgentResponse<R>.self, from: responseData)
        } catch {
            throw AppError.agentUnavailable("Malformed agent response")
        }
        guard envelope.ok else {
            throw AppError.agentUnavailable(envelope.error ?? "Agent rejected \(command.rawValue)")
        }
        if let data = envelope.data { return data }
        // `null` data is valid for fire-and-forget commands.
        if let ignored = try? decoder.decode(R.self, from: Data("null".utf8)) { return ignored }
        throw AppError.agentUnavailable("Empty agent response")
    }

    private func readIPCToken() throws -> String {
        let url = options.tokenURL
        // Refuse a token file that other users could read or that is a symlink.
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        guard let attributes else { throw AppError.agentUnavailable("Agent is not running") }
        if attributes[.type] as? FileAttributeType == .typeSymbolicLink {
            throw AppError.agentUnavailable("Insecure agent token")
        }
        if let perms = attributes[.posixPermissions] as? NSNumber, perms.intValue & 0o077 != 0 {
            throw AppError.agentUnavailable("Insecure agent token permissions")
        }
        if let owner = attributes[.ownerAccountID] as? NSNumber, owner.uint32Value != getuid() {
            throw AppError.agentUnavailable("Agent token owned by another user")
        }
        guard let token = try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            throw AppError.agentUnavailable("Agent token unreadable")
        }
        return token
    }

    private func exchange(_ request: Data) async throws -> Data {
        let endpoint = NWEndpoint.unix(path: options.socketURL.path)
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = nil
        let connection = NWConnection(to: endpoint, using: parameters)
        let timeout = options.timeout
        let queue = self.queue

        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await Self.run(connection: connection, request: request, queue: queue)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw AppError.agentUnavailable("Agent timed out")
            }
            defer {
                group.cancelAll()
                connection.cancel()
            }
            guard let result = try await group.next() else { throw AppError.agentUnavailable("No response") }
            return result
        }
    }

    private static func run(connection: NWConnection, request: Data, queue: DispatchQueue) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                let box = ResumeOnce(continuation)
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        connection.send(content: request, completion: .contentProcessed { error in
                            if error != nil { box.resume(throwing: AppError.agentUnavailable("Send failed")); return }
                            receiveLine(connection: connection, buffer: Data(), box: box)
                        })
                    case .failed, .waiting:
                        box.resume(throwing: AppError.agentUnavailable("Agent is not running"))
                    case .cancelled:
                        box.resume(throwing: AppError.cancelled)
                    default:
                        break
                    }
                }
                connection.start(queue: queue)
            }
        } onCancel: {
            connection.cancel()
        }
    }

    private static func receiveLine(connection: NWConnection, buffer: Data, box: ResumeOnce) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { content, _, isComplete, error in
            var accumulated = buffer
            if let content { accumulated.append(content) }
            if let newline = accumulated.firstIndex(of: 0x0A) {
                box.resume(returning: accumulated.prefix(upTo: newline))
                return
            }
            if accumulated.count > maxResponseBytes {
                box.resume(throwing: AppError.agentUnavailable("Agent response too large"))
                return
            }
            if error != nil || isComplete {
                if !accumulated.isEmpty, isComplete { box.resume(returning: accumulated); return }
                box.resume(throwing: AppError.agentUnavailable("Connection closed"))
                return
            }
            receiveLine(connection: connection, buffer: accumulated, box: box)
        }
    }
}

/// Guards a checked continuation against double resumption from racing
/// NWConnection callbacks.
private final class ResumeOnce: @unchecked Sendable {
    private var continuation: CheckedContinuation<Data, Error>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<Data, Error>) { self.continuation = continuation }

    func resume(returning value: Data) {
        lock.withLock {
            continuation?.resume(returning: value)
            continuation = nil
        }
    }

    func resume(throwing error: Error) {
        lock.withLock {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
