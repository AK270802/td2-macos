import SwiftUI
import Observation
import EffiLensKit

// MARK: - Shared: assigned projects/tasks (GET /projects/assigned)

@MainActor
@Observable
final class AssignedWorkModel {
    private(set) var projects: Loadable<[AssignedProject]> = .idle
    private let work: WorkService

    init(environment: AppEnvironment) { work = environment.work }

    func load() async {
        if projects.value == nil { projects = .loading }
        do { projects = .loaded(try await work.assignedProjects().sorted { $0.name.localizedCompare($1.name) == .orderedAscending }) }
        catch { projects = .failed(DashboardViewModel.map(error)) }
    }

    static func ref(_ task: AssignedTask, in project: AssignedProject) -> AgentTaskRef {
        AgentTaskRef(taskId: task.id.uuidString.lowercased(), projectId: project.id.uuidString.lowercased(),
                     taskName: task.name, projectName: project.name)
    }
}

/// "Track" button used by Tracker / Projects / Tasks. Selecting a task goes
/// through the agent (`select_task`), which starts the timer — the only
/// timer logic lives in the Rust agent (`common::timer_state`).
struct TrackTaskButton: View {
    @Environment(AppModel.self) private var model
    let task: AssignedTask
    let project: AssignedProject

    private var isCurrent: Bool {
        model.timerState?.task?.taskId == task.id.uuidString.lowercased() && model.timerState?.state == .running
    }

    var body: some View {
        if isCurrent {
            StatusPill(text: "Tracking", tone: .success)
        } else {
            Button {
                let ref = AssignedWorkModel.ref(task, in: project)
                Task { await model.runAgent { try await $0.selectTask(ref) } }
            } label: {
                Label("Track", systemImage: "play.fill")
            }
            .controlSize(.small)
            .disabled(!model.isAgentConnected)
            .help(model.isAgentConnected ? "Start tracking this task" : "The tracking agent is not running")
        }
    }
}

// MARK: - Tracker

struct TrackerView: View {
    @Environment(AppModel.self) private var model
    @State private var work: AssignedWorkModel
    @State private var stats: AgentLocalTimeStats?
    @State private var search = ""
    @State private var showBreakSheet = false

    init(environment: AppEnvironment) {
        _work = State(initialValue: AssignedWorkModel(environment: environment))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                AgentStatusNotice()
                timerHero
                todayStats
                Card("Select a task", subtitle: "Choose what you're working on. The timer starts when you pick a task.") {
                    TextField("Search tasks", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                    LoadStateView(state: work.projects, emptyTitle: "No assigned tasks",
                                  emptyMessage: "Ask your manager to assign you to a project.", emptySymbol: "checklist",
                                  isEmpty: { $0.allSatisfy { $0.tasks.isEmpty } },
                                  retry: { Task { await work.load() } }) { projects in
                        TaskPickerList(projects: projects, search: search)
                    }
                }
            }
            .padding(Space.xl)
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .task { await work.load() }
        .task(id: model.isAgentConnected) {
            while !Task.isCancelled, model.isAgentConnected {
                stats = try? await model.environment?.agent?.localTimeStats()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .sheet(isPresented: $showBreakSheet) { BreakSheet() }
    }

    private var timerHero: some View {
        let state = model.timerState
        return Card {
            HStack(alignment: .center, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text(phaseText(state)).font(Typo.overline).foregroundStyle(Palette.textSecondary)
                    Text(Format.clock(state?.elapsedSecs ?? 0))
                        .font(Typo.timerHero).monospacedDigit()
                        .foregroundStyle(state?.state == .running ? Palette.textPrimary : Palette.textSecondary)
                        .contentTransition(.numericText())
                        .accessibilityLabel("Elapsed \(Format.duration(state?.elapsedSecs ?? 0))")
                    if let task = state?.task {
                        Text("\(task.projectName) · \(task.taskName)").font(Typo.body).foregroundStyle(Palette.textSecondary)
                    } else {
                        Text("No task selected").font(Typo.body).foregroundStyle(Palette.textTertiary)
                    }
                    if state?.inMeeting == true { StatusPill(text: "In a meeting", tone: .info) }
                    if let remaining = state?.breakRemainingSecs, state?.state == .onBreak {
                        StatusPill(text: "Break · \(Format.clock(remaining)) left", tone: .warning)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: Space.s) {
                    HStack {
                        Button {
                            Task { await model.runAgent { try await $0.togglePlayPause() } }
                        } label: {
                            Label(state?.state == .running ? "Pause" : "Resume",
                                  systemImage: state?.state == .running ? "pause.fill" : "play.fill")
                                .frame(minWidth: 90)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(state?.task == nil)
                        .keyboardShortcut(.space, modifiers: [.control, .option])

                        Button(role: .destructive) {
                            Task { await model.runAgent { try await $0.stopTracking() } }
                        } label: { Label("Stop", systemImage: "stop.fill") }
                        .controlSize(.large)
                        .disabled(state == nil || state?.state == .idle)
                    }
                    Button("Take a Break…") { showBreakSheet = true }
                        .disabled(state?.state != .running)
                }
                .disabled(!model.isAgentConnected)
            }
        }
    }

    private var todayStats: some View {
        HStack(spacing: Space.l) {
            StatTile(label: "Today", value: stats.map { Format.duration($0.workedTodaySec) } ?? "—")
            StatTile(label: "This week", value: stats.map { Format.duration($0.workedWeekSec) } ?? "—")
            StatTile(label: "Sessions today", value: stats.map { "\($0.sessionsToday)" } ?? "—")
            StatTile(label: "Meetings today", value: stats.map { Format.duration($0.meetingTodaySec) } ?? "—")
        }
        .help("Recorded on this Mac by the tracking agent; the server totals in History include other devices.")
    }

    private func phaseText(_ state: AgentTimerState?) -> String {
        switch state?.state {
        case .running: return "TRACKING"
        case .paused: return "PAUSED"
        case .onBreak: return "ON BREAK"
        case .idle: return "READY"
        case .none: return "AGENT OFFLINE"
        }
    }
}

struct TaskPickerList: View {
    let projects: [AssignedProject]
    let search: String

    var body: some View {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        VStack(alignment: .leading, spacing: Space.m) {
            ForEach(projects) { project in
                let tasks = project.tasks.filter { query.isEmpty || $0.name.lowercased().contains(query) || project.name.lowercased().contains(query) }
                if !tasks.isEmpty {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(project.name).font(Typo.overline).foregroundStyle(Palette.textSecondary)
                        ForEach(tasks) { task in
                            HStack {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(task.name).font(Typo.bodyEmphasis)
                                    if let d = task.description, !d.isEmpty {
                                        Text(d).font(Typo.caption).foregroundStyle(Palette.textSecondary).lineLimit(1)
                                    }
                                }
                                Spacer()
                                TrackTaskButton(task: task, project: project)
                            }
                            .padding(.vertical, Space.xs)
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

/// Break picker → agent `start_break`. Paid/unpaid accounting is decided by
/// the organisation's `breaks_are_paid` setting on the server.
struct BreakSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = 15
    @State private var kind = "short"

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Take a break").font(Typo.title)
            Picker("Type", selection: $kind) {
                Text("Short break").tag("short")
                Text("Lunch").tag("lunch")
                Text("Personal").tag("personal")
            }
            Stepper("Duration: \(minutes) min", value: $minutes, in: 5...120, step: 5)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Start Break") {
                    let payload = AgentBreakPayload(breakType: kind, durationSecs: minutes * 60)
                    Task {
                        await model.runAgent { try await $0.startBreak(payload) }
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.xl)
        .frame(width: 380)
    }
}

/// Explains why tracking controls are disabled (agent offline / legacy app).
struct AgentStatusNotice: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.agentLink {
        case .unavailable, .unknown:
            notice(symbol: "bolt.horizontal.circle", tone: Palette.warning,
                   text: model.agentRegistration == .notBundled
                       ? "This build does not include the tracking agent. Time tracking is unavailable."
                       : model.agentRegistration == .requiresApproval
                           ? "Allow EffiLens in System Settings › General › Login Items so the tracking agent can run."
                           : "The tracking agent is not responding. Tracking is paused until it reconnects.") {
                if model.agentRegistration == .requiresApproval {
                    Button("Open Login Items") { AgentLifecycle.openLoginItemsSettings() }
                } else if model.agentRegistration != .notBundled {
                    Button("Reconnect") { model.restartAgentConnection() }
                }
            }
        case .legacyConflict:
            notice(symbol: "exclamationmark.triangle", tone: Palette.warning,
                   text: "The older WorkPulse app is running. Quit it to track time here — running both would record time twice.") { EmptyView() }
        case .connected:
            EmptyView()
        }
    }

    private func notice<A: View>(symbol: String, tone: Color, text: String, @ViewBuilder action: () -> A) -> some View {
        HStack(spacing: Space.m) {
            Image(systemName: symbol).foregroundStyle(tone)
            Text(text).font(Typo.body).fixedSize(horizontal: false, vertical: true)
            Spacer()
            action()
        }
        .padding(Space.m)
        .background(tone.opacity(0.10), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

// MARK: - Projects

struct ProjectsView: View {
    @State private var work: AssignedWorkModel
    @State private var summary: Loadable<ProjectTimeSummaryResponse> = .idle
    @State private var expanded: Set<UUID> = []
    private let service: WorkService

    init(environment: AppEnvironment) {
        _work = State(initialValue: AssignedWorkModel(environment: environment))
        service = environment.work
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                AgentStatusNotice()
                LoadStateView(state: work.projects, emptyTitle: "No projects", emptyMessage: "You are not assigned to any project yet.",
                              emptySymbol: "folder", isEmpty: { $0.isEmpty }, retry: { Task { await work.load() } }) { projects in
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: Space.l)], alignment: .leading, spacing: Space.l) {
                        ForEach(projects) { project in projectCard(project) }
                    }
                }
            }
            .padding(Space.xl)
        }
        .task {
            await work.load()
            do { summary = .loaded(try await service.projectSummary(range: .thisWeek())) } catch { summary = .failed(DashboardViewModel.map(error)) }
        }
    }

    private func weekSeconds(_ project: AssignedProject) -> Int? {
        summary.value?.items.first { $0.projectId == project.id }?.totalDurationSec ?? (summary.value == nil ? nil : 0)
    }

    private func projectCard(_ project: AssignedProject) -> some View {
        Card(project.name, subtitle: project.description) {
            HStack {
                StatusPill(text: "\(project.tasks.count) task\(project.tasks.count == 1 ? "" : "s")", tone: .neutral)
                Spacer()
                Text(weekSeconds(project).map { "\(Format.duration($0)) this week" } ?? "—")
                    .font(Typo.caption).foregroundStyle(Palette.textSecondary)
            }
            DisclosureGroup(isExpanded: Binding(get: { expanded.contains(project.id) },
                                                set: { if $0 { expanded.insert(project.id) } else { expanded.remove(project.id) } })) {
                ForEach(project.tasks) { task in
                    HStack {
                        Text(task.name).font(Typo.body)
                        Spacer()
                        TrackTaskButton(task: task, project: project)
                    }
                    .padding(.vertical, Space.xxs)
                }
            } label: { Text("Tasks").font(Typo.bodyEmphasis) }
        }
    }
}

// MARK: - Assigned tasks

struct TasksView: View {
    @State private var work: AssignedWorkModel
    @State private var search = ""
    @State private var summary: TaskTimeSummaryResponse?
    private let service: WorkService

    init(environment: AppEnvironment) {
        _work = State(initialValue: AssignedWorkModel(environment: environment))
        service = environment.work
    }

    private struct Row: Identifiable {
        let task: AssignedTask
        let project: AssignedProject
        var id: UUID { task.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            AgentStatusNotice().padding([.horizontal, .top], Space.xl)
            LoadStateView(state: work.projects, emptyTitle: "No assigned tasks", emptySymbol: "checklist",
                          isEmpty: { $0.allSatisfy { $0.tasks.isEmpty } }, retry: { Task { await work.load() } }) { projects in
                let query = search.lowercased()
                let rows = projects.flatMap { p in p.tasks.map { Row(task: $0, project: p) } }
                    .filter { query.isEmpty || $0.task.name.lowercased().contains(query) || $0.project.name.lowercased().contains(query) }
                Table(rows) {
                    TableColumn("Task") { row in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(row.task.name).font(Typo.bodyEmphasis)
                            if let d = row.task.description, !d.isEmpty { Text(d).font(Typo.caption).foregroundStyle(Palette.textSecondary).lineLimit(1) }
                        }
                    }
                    TableColumn("Project") { row in Text(row.project.name) }
                    TableColumn("This week") { row in
                        let sec = summary?.items.first { $0.taskId == row.task.id }?.totalDurationSec
                        Text(sec.map(Format.duration) ?? "—").monospacedDigit()
                    }
                    .width(90)
                    TableColumn("") { row in TrackTaskButton(task: row.task, project: row.project) }
                        .width(100)
                }
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search tasks")
        .task {
            await work.load()
            summary = try? await service.taskSummary(range: .thisWeek())
        }
    }
}

// MARK: - History (GET /task-time)

@MainActor
@Observable
final class HistoryViewModel {
    enum Period: String, CaseIterable, Identifiable {
        case today = "Today", week = "This Week", month = "This Month"
        var id: String { rawValue }
        var range: DateRange {
            switch self {
            case .today: return .today()
            case .week: return .thisWeek()
            case .month:
                let cal = Calendar.current
                let now = Date()
                let start = cal.dateInterval(of: .month, for: now)?.start ?? now
                return DateRange(from: CalendarDate(start), to: CalendarDate(now))
            }
        }
    }

    var period: Period = .week
    private(set) var logs: Loadable<TaskTimeLogListResponse> = .idle
    private let work: WorkService

    init(environment: AppEnvironment) { work = environment.work }

    func load() async {
        logs = .loading
        do { logs = .loaded(try await work.timeLogs(range: period.range, pageSize: 200)) }
        catch { logs = .failed(DashboardViewModel.map(error)) }
    }
}

struct HistoryView: View {
    @State private var viewModel: HistoryViewModel

    init(environment: AppEnvironment) { _viewModel = State(initialValue: HistoryViewModel(environment: environment)) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Picker("Period", selection: $viewModel.period) {
                    ForEach(HistoryViewModel.Period.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                Spacer()
                if let total = viewModel.logs.value.map({ $0.items.reduce(0) { $0 + $1.durationSec } }) {
                    Text("Total \(Format.duration(total))").font(Typo.bodyEmphasis).monospacedDigit()
                }
            }
            .padding([.horizontal, .top], Space.xl)

            LoadStateView(state: viewModel.logs, emptyTitle: "No time recorded", emptyMessage: "Sessions you track appear here after they sync.",
                          emptySymbol: "clock", isEmpty: { $0.items.isEmpty }, retry: { Task { await viewModel.load() } }) { page in
                Table(page.items.sorted { $0.startedAt > $1.startedAt }) {
                    TableColumn("Date") { log in Text(log.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) }
                        .width(110)
                    TableColumn("Time") { log in Text("\(Format.time(log.startedAt)) – \(Format.time(log.endedAt))").monospacedDigit() }
                        .width(140)
                    TableColumn("Task") { log in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(log.isBreak == true ? "Break" : log.taskName).font(Typo.bodyEmphasis)
                            Text(log.projectName).font(Typo.caption).foregroundStyle(Palette.textSecondary)
                        }
                    }
                    TableColumn("Duration") { log in Text(Format.duration(log.durationSec)).monospacedDigit() }
                        .width(80)
                    TableColumn("Type") { log in
                        if log.isManual { StatusPill(text: "Manual", tone: .info) }
                        else if log.isBreak == true { StatusPill(text: "Break", tone: .warning) }
                        else { StatusPill(text: "Tracked", tone: .neutral) }
                    }
                    .width(80)
                }
                if page.total > page.items.count {
                    Text("Showing \(page.items.count) of \(page.total) entries.").font(Typo.caption).foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, Space.xl)
                }
            }
        }
        .task(id: viewModel.period) { await viewModel.load() }
    }
}

// MARK: - Manual entry (POST /task-time/manual — admin+)

struct ManualEntryView: View {
    @Environment(AppModel.self) private var model
    @State private var work: AssignedWorkModel
    @State private var selectedTask: UUID?
    @State private var start = Calendar.current.date(byAdding: .hour, value: -1, to: Date()) ?? Date()
    @State private var end = Date()
    @State private var submitting = false
    @State private var result: Result<ManualTimeLogOut, AppError>?
    private let service: WorkService

    init(environment: AppEnvironment) {
        _work = State(initialValue: AssignedWorkModel(environment: environment))
        service = environment.work
    }

    private struct Choice: Identifiable {
        let project: AssignedProject
        let task: AssignedTask
        var id: UUID { task.id }
    }

    private var choices: [Choice] {
        (work.projects.value ?? []).flatMap { p in p.tasks.map { Choice(project: p, task: $0) } }
    }

    private var validationMessage: String? {
        if selectedTask == nil { return "Choose a task." }
        if end <= start { return "End time must be after start time." }
        if end > Date() { return "Entries can't be in the future." }
        return nil
    }

    var body: some View {
        Form {
            Section {
                Text("Add time you worked without the tracker. The server validates overlaps and records who created the entry.")
                    .font(Typo.caption).foregroundStyle(Palette.textSecondary)
            }
            Section("Entry") {
                Picker("Task", selection: $selectedTask) {
                    Text("Choose…").tag(UUID?.none)
                    ForEach(choices) { choice in
                        Text("\(choice.project.name) · \(choice.task.name)").tag(Optional(choice.task.id))
                    }
                }
                DatePicker("Start", selection: $start, in: ...Date())
                DatePicker("End", selection: $end, in: ...Date())
                LabeledContent("Duration", value: Format.duration(Int(max(0, end.timeIntervalSince(start)))))
                LabeledContent("For", value: model.user?.displayName ?? "—")
            }
            Section {
                if let message = validationMessage { Text(message).font(Typo.caption).foregroundStyle(Palette.textSecondary) }
                if case .failure(let error) = result { Label(error.userMessage, systemImage: "exclamationmark.circle").foregroundStyle(Palette.danger) }
                if case .success(let log) = result {
                    Label("Saved \(Format.duration(log.durationSec)) on \(log.taskName ?? "task").", systemImage: "checkmark.circle").foregroundStyle(Palette.success)
                }
                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        if submitting { ProgressView().controlSize(.small) }
                        Text("Save Entry")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(validationMessage != nil || submitting)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 640)
        .task { await work.load() }
    }

    private func submit() async {
        guard let user = model.user, let taskId = selectedTask,
              let choice = choices.first(where: { $0.task.id == taskId }) else { return }
        submitting = true
        defer { submitting = false }
        let body = ManualTimeLogCreate(userId: user.id, taskId: taskId, projectId: choice.project.id,
                                       startedAt: start, endedAt: end, timezone: TimeZone.current.identifier)
        do { result = .success(try await service.createManualLog(body)) }
        catch { result = .failure(DashboardViewModel.map(error)) }
    }
}
