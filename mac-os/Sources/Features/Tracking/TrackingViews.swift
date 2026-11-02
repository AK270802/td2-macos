import AppKit
import SwiftUI
import Observation
import UniformTypeIdentifiers
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

/// A task with its project (flattened for lists).
struct TaskChoice: Identifiable, Hashable {
    let project: AssignedProject
    let task: AssignedTask
    var id: UUID { task.id }

    static func all(_ projects: [AssignedProject]) -> [TaskChoice] {
        projects.flatMap { p in p.tasks.map { TaskChoice(project: p, task: $0) } }
    }
}

extension AppModel {
    func isCurrent(_ task: AssignedTask) -> Bool {
        timerState?.task?.taskId == task.id.uuidString.lowercased()
    }

    /// Selecting a task goes through the agent (`select_task`), which starts
    /// the timer — the only timer logic lives in `common::timer_state`.
    func track(_ choice: TaskChoice) {
        let ref = AssignedWorkModel.ref(choice.task, in: choice.project)
        Task {
            await ensureAgentSession()
            await refreshPermissions()   // banner reflects the state at tracking start
            await runAgent { try await $0.selectTask(ref) }
        }
    }
}

/// "Track" button used by Projects / Tasks rows.
struct TrackTaskButton: View {
    @Environment(AppModel.self) private var model
    let task: AssignedTask
    let project: AssignedProject

    var body: some View {
        if model.isCurrent(task), model.timerState?.state == .running {
            Pill(text: "● Tracking", kind: .ok)
        } else {
            Button {
                model.track(TaskChoice(project: project, task: task))
            } label: {
                Label("Track", systemImage: "play.fill")
            }
            .buttonStyle(.effi)
            .disabled(!model.isAgentConnected)
            .help(model.isAgentConnected ? "Start tracking this task" : "The tracking agent is not running")
        }
    }
}

// MARK: - Tracker (prototype V.tracker: 1.3 : 1)

struct TrackerView: View {
    @Environment(AppModel.self) private var model
    @State private var work: AssignedWorkModel
    @State private var search = ""
    @State private var showBreakSheet = false

    init(environment: AppEnvironment) {
        _work = State(initialValue: AssignedWorkModel(environment: environment))
    }

    var body: some View {
        Page {
            AgentStatusNotice()
            FractionalColumns(ratio: 1.3) {
                timerCard
                quickSwitch
            }
        }
        .task { await work.load() }
        .sheet(isPresented: $showBreakSheet) { BreakSheet() }
    }

    private var statusText: (String, Color) {
        switch model.timerState?.state {
        case .running: return ("● Recording", Palette.success)
        case .paused: return ("Paused", Palette.textTertiary)
        case .onBreak: return ("On break", Palette.warning)
        case .idle: return ("Ready", Palette.textTertiary)
        case .none: return (model.agentLink == .legacyConflict ? "Blocked by the older app" : "Agent offline", Palette.textTertiary)
        }
    }

    private var timerCard: some View {
        let state = model.timerState
        let running = state?.state == .running
        let elapsed = state?.elapsedSecs ?? 0
        return Card(padding: 34) {
            VStack(spacing: 0) {
                Text(state?.task?.projectName ?? "Select a task to start").font(Typo.caption).foregroundStyle(Palette.textTertiary)
                Text(state?.task?.taskName ?? "No task selected").font(.system(size: 19, weight: .semibold)).padding(.top, 4).multilineTextAlignment(.center)
                ProgressRing(progress: Double(elapsed % 3600) / 3600, lineWidth: 14) {
                    VStack(spacing: 2) {
                        Text(Format.clock(elapsed)).font(Typo.timerHero).tracking(-2).monospacedDigit()
                            .contentTransition(.numericText())
                            .accessibilityLabel("Elapsed \(Format.duration(elapsed))")
                        Text(statusText.0).font(Typo.body).foregroundStyle(statusText.1)
                        if let remaining = state?.breakRemainingSecs, state?.state == .onBreak {
                            Text("\(Format.clock(remaining)) left").font(Typo.caption).foregroundStyle(Palette.warning)
                        }
                        if state?.inMeeting == true { Pill(text: "In a meeting", kind: .blue) }
                    }
                }
                .frame(width: 250, height: 250)
                .padding(.vertical, 24)
                HStack(spacing: 8) {
                    Button {
                        Task { await model.runAgent { try await $0.togglePlayPause() } }
                    } label: {
                        Label(running ? "Pause" : (elapsed > 0 ? "Resume" : "Start"), systemImage: running ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.effiButton(running ? .normal : .primary, .large))
                    .disabled(state?.task == nil)
                    Button("Stop & Save") { Task { await model.runAgent { try await $0.stopTracking() } } }
                        .buttonStyle(.effiButton(.normal, .large))
                        .disabled(state == nil || state?.state == .idle)
                    Button("Break…") { showBreakSheet = true }
                        .buttonStyle(.effiButton(.normal, .large))
                        .disabled(!running)
                }
                .disabled(!model.isAgentConnected)
                Text("⌃⌥Space start/pause · ⌃⌥S stop · ⇧⌘M mini timer").font(Typo.caption).foregroundStyle(Palette.textTertiary).padding(.top, 14)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var quickSwitch: some View {
        Card("Quick switch task") {
            EffiTextField(placeholder: "Search tasks…", text: $search).padding(.bottom, 2)
            LoadStateView(state: work.projects, emptyTitle: "No assigned tasks", emptyMessage: "Ask your manager to assign you to a project.",
                          emptySymbol: "checklist", isEmpty: { $0.allSatisfy { $0.tasks.isEmpty } },
                          retry: { Task { await work.load() } }) { projects in
                let query = search.trimmingCharacters(in: .whitespaces).lowercased()
                let choices = TaskChoice.all(projects).filter { query.isEmpty || $0.task.name.lowercased().contains(query) || $0.project.name.lowercased().contains(query) }
                VStack(spacing: 8) {
                    ForEach(choices) { choice in
                        Button {
                            model.track(choice)
                        } label: {
                            TaskRowCard(title: choice.task.name, subtitle: choice.project.name,
                                        dot: IdentityColor.color(for: choice.project.id), selected: model.isCurrent(choice.task)) {
                                if model.isCurrent(choice.task) {
                                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.accent)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!model.isAgentConnected)
                    }
                    if choices.isEmpty { EmptyStateView(title: "No matching tasks", symbol: "magnifyingglass") }
                }
            }
        }
    }
}

/// Break picker → agent `start_break`. Paid/unpaid accounting follows the
/// organisation's `breaks_are_paid` setting on the server.
struct BreakSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = 15
    @State private var kind = "short"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Take a break").font(Typo.title)
            FieldLabel("Type")
            EffiSegmented(selection: $kind, options: [("short", "Short break"), ("lunch", "Lunch"), ("personal", "Personal")])
            FieldLabel("Duration")
            EffiSegmented(selection: $minutes, options: [(5, "5 min"), (15, "15 min"), (30, "30 min"), (60, "60 min")])
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.effi).keyboardShortcut(.cancelAction)
                Button("Start Break") {
                    let payload = AgentBreakPayload(breakType: kind, durationSecs: minutes * 60)
                    Task {
                        await model.runAgent { try await $0.startBreak(payload) }
                        dismiss()
                    }
                }
                .buttonStyle(.effiPrimary)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 20)
        }
        .padding(22)
        .frame(width: 400)
        .background(Palette.surfaceRaised)
    }
}

/// Explains why tracking controls are disabled (agent offline / legacy app).
struct AgentStatusNotice: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.agentLink {
        case .unavailable, .unknown:
            notice(symbol: "bolt.horizontal.circle",
                   text: model.agentRegistration == .notBundled
                       ? "This build does not include the tracking agent. Time tracking is unavailable."
                       : model.agentRegistration == .requiresApproval
                           ? "Allow EffiLens in System Settings › General › Login Items so the tracking agent can run."
                           : "The tracking agent is not responding. Tracking is paused until it reconnects.") {
                if model.agentRegistration == .requiresApproval {
                    Button("Open Login Items") { AgentLifecycle.openLoginItemsSettings() }.buttonStyle(.effi)
                } else if model.agentRegistration != .notBundled {
                    Button("Reconnect") { model.restartAgentConnection() }.buttonStyle(.effi)
                }
            }
        case .legacyConflict:
            notice(symbol: "exclamationmark.triangle",
                   text: "The older WorkPulse app is running. Quit it to track time here — running both would record time twice.") { EmptyView() }
        case .connected:
            EmptyView()
        }
    }

    private func notice<A: View>(symbol: String, text: String, @ViewBuilder action: () -> A) -> some View {
        HStack(spacing: Space.m) {
            Image(systemName: symbol).foregroundStyle(Palette.warning)
            Text(text).font(Typo.body).foregroundStyle(Palette.textPrimary).fixedSize(horizontal: false, vertical: true)
            Spacer()
            action()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Palette.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.group, style: .continuous).strokeBorder(Palette.warning.opacity(0.25)))
    }
}

// MARK: - Projects (prototype V.projects: 2-column cards)

struct ProjectsView: View {
    @Environment(Navigator.self) private var navigator
    @State private var work: AssignedWorkModel
    @State private var summary: ProjectTimeSummaryResponse?
    private let service: WorkService

    init(environment: AppEnvironment) {
        _work = State(initialValue: AssignedWorkModel(environment: environment))
        service = environment.work
    }

    var body: some View {
        Page {
            AgentStatusNotice()
            LoadStateView(state: work.projects, emptyTitle: "No projects", emptyMessage: "You are not assigned to any project yet.",
                          emptySymbol: "folder", isEmpty: { $0.isEmpty }, retry: { Task { await work.load() } }) { projects in
                EqualColumns(count: 2) {
                    ForEach(projects) { project in projectCard(project) }
                }
            }
        }
        .task {
            await work.load()
            summary = try? await service.projectSummary(range: .thisWeek())
        }
    }

    private func weekSeconds(_ project: AssignedProject) -> Int? {
        guard let summary else { return nil }
        return summary.items.first { $0.projectId == project.id }?.totalDurationSec ?? 0
    }

    private static func share(week: Int?, total: Int?) -> Double {
        guard let week, let total, week > 0, total > 0 else { return 0 }
        return Double(week) / Double(total)
    }

    private func projectCard(_ project: AssignedProject) -> some View {
        let tint = IdentityColor.color(for: project.id)
        let week = weekSeconds(project)
        let share = Self.share(week: week, total: summary?.totalDurationSec)
        return Card {
            HStack(spacing: Space.m) {
                IconTile(symbol: "folder", tint: tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(project.name).font(.system(size: 14, weight: .bold)).lineLimit(1)
                    Text(project.description?.isEmpty == false ? project.description! : "No description")
                        .font(Typo.caption).foregroundStyle(Palette.textTertiary).lineLimit(1)
                }
                Spacer()
                Pill(text: "\(project.tasks.count) task\(project.tasks.count == 1 ? "" : "s")", kind: .gray)
            }
            HStack {
                Text("Share of your week").font(Typo.body).foregroundStyle(Palette.textTertiary)
                Spacer()
                Text("\(Int((share * 100).rounded()))%").font(Typo.mono)
            }
            .padding(.top, 6)
            ProgressBar(value: share, tint: tint)
            HStack {
                (Text(week.map(Format.duration) ?? "—").font(Typo.mono) + Text(" this week").font(Typo.body).foregroundColor(Palette.textTertiary))
                Spacer()
                Button("View Tasks") {
                    navigator.taskProjectFilter = project.id
                    navigator.go(.tasks)
                }
                .buttonStyle(.effi)
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Assigned tasks (prototype V.tasks)

struct TasksView: View {
    private static func subtitle(_ row: TaskChoice) -> String {
        guard let description = row.task.description, !description.isEmpty else { return row.project.name }
        return "\(row.project.name) · \(description)"
    }

    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator
    @State private var work: AssignedWorkModel
    @State private var search = ""
    @State private var projectFilter: UUID?
    @State private var summary: TaskTimeSummaryResponse?
    private let service: WorkService

    init(environment: AppEnvironment) {
        _work = State(initialValue: AssignedWorkModel(environment: environment))
        service = environment.work
    }

    var body: some View {
        Page {
            AgentStatusNotice()
            HStack(spacing: 10) {
                EffiTextField(placeholder: "Search tasks…", text: $search).frame(maxWidth: 320)
                FieldChrome {
                    Picker("Project", selection: $projectFilter) {
                        Text("All projects").tag(UUID?.none)
                        ForEach(work.projects.value ?? []) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .pickerStyle(.menu)
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: 220)
                Spacer()
            }
            LoadStateView(state: work.projects, emptyTitle: "No assigned tasks", emptySymbol: "checklist",
                          isEmpty: { $0.allSatisfy { $0.tasks.isEmpty } }, retry: { Task { await work.load() } }) { projects in
                let query = search.lowercased()
                let rows = TaskChoice.all(projects)
                    .filter { projectFilter == nil || $0.project.id == projectFilter }
                    .filter { query.isEmpty || $0.task.name.lowercased().contains(query) || $0.project.name.lowercased().contains(query) }
                VStack(spacing: 8) {
                    ForEach(rows) { row in
                        TaskRowCard(title: row.task.name,
                                    subtitle: Self.subtitle(row),
                                    dot: IdentityColor.color(for: row.project.id), selected: model.isCurrent(row.task)) {
                            if let sec = summary?.items.first(where: { $0.taskId == row.task.id })?.totalDurationSec {
                                Text("\(Format.duration(sec)) this week").font(Typo.caption).foregroundStyle(Palette.textTertiary).monospacedDigit()
                            }
                            TrackTaskButton(task: row.task, project: row.project)
                        }
                    }
                    if rows.isEmpty { EmptyStateView(title: "No matching tasks", symbol: "magnifyingglass") }
                }
            }
        }
        .onAppear {
            projectFilter = navigator.taskProjectFilter
            navigator.taskProjectFilter = nil
        }
        .task {
            await work.load()
            summary = try? await service.taskSummary(range: .thisWeek())
        }
    }
}

// MARK: - History (prototype V.history; GET /task-time)

@MainActor
@Observable
final class HistoryViewModel {
    enum Period: String, CaseIterable, Identifiable {
        case day = "Day", week = "Week", month = "Month"
        var id: String { rawValue }
        var range: DateRange {
            switch self {
            case .day: return .today()
            case .week: return .thisWeek()
            case .month:
                let cal = Calendar.current
                let now = Date()
                let start = cal.dateInterval(of: .month, for: now)?.start ?? now
                return DateRange(from: CalendarDate(start), to: CalendarDate(now))
            }
        }
    }

    var period: Period = .day
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
    @State private var exportError: String?

    init(environment: AppEnvironment) { _viewModel = State(initialValue: HistoryViewModel(environment: environment)) }

    private var sessions: [TaskTimeLog] {
        (viewModel.logs.value?.items ?? []).filter { $0.isBreak != true }.sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        Page {
            HStack {
                EffiSegmented(selection: $viewModel.period, options: HistoryViewModel.Period.allCases.map { ($0, $0.rawValue) })
                Spacer()
                if let exportError { Text(exportError).font(Typo.caption).foregroundStyle(Palette.danger) }
                Button("Export CSV") { exportCSV() }.buttonStyle(.effi).disabled(sessions.isEmpty)
            }
            LoadStateView(state: viewModel.logs, retry: { Task { await viewModel.load() } }) { _ in
                let total = sessions.reduce(0) { $0 + $1.durationSec }
                EqualColumns(count: 3) {
                    StatTile(label: "Total", value: Format.duration(total))
                    StatTile(label: "Sessions", value: "\(sessions.count)")
                    StatTile(label: "Avg. session", value: sessions.isEmpty ? "—" : Format.duration(total / sessions.count))
                }
                if sessions.isEmpty {
                    Card { EmptyStateView(title: "No time recorded", message: "Sessions you track appear here after they sync.", symbol: "clock") }
                } else {
                    ForEach(groups, id: \.day) { group in
                        Card(group.title, trailing: AnyView(Text("\(group.logs.count) session\(group.logs.count == 1 ? "" : "s")").font(Typo.mono))) {
                            EffiTable<TaskTimeLog>(rows: group.logs, columns: [
                                .init("Task") { log in Text(log.taskName) },
                                .init("Project") { log in Text(log.projectName).foregroundStyle(Palette.textSecondary) },
                                .init("Start", width: 90) { log in Text(Format.time(log.startedAt)).font(Typo.mono) },
                                .init("End", width: 90) { log in Text(Format.time(log.endedAt)).font(Typo.mono) },
                                .init("Duration", width: 100) { log in
                                    HStack(spacing: 6) {
                                        Text(Format.duration(log.durationSec)).font(.system(size: 13, weight: .bold, design: .monospaced))
                                        if log.isManual { Pill(text: "Manual", kind: .blue) }
                                    }
                                },
                            ])
                        }
                    }
                }
            }
        }
        .task(id: viewModel.period) { await viewModel.load() }
    }

    private struct DayGroup {
        let day: CalendarDate
        let title: String
        let logs: [TaskTimeLog]
    }

    private var groups: [DayGroup] {
        let grouped = Dictionary(grouping: sessions) { CalendarDate($0.startedAt) }
        return grouped.keys.sorted(by: >).map { day in
            let title = day.date().map { Calendar.current.isDateInToday($0) ? "Today" : $0.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)) } ?? day.description
            return DayGroup(day: day, title: title, logs: grouped[day] ?? [])
        }
    }

    /// Writes the fetched logs to a CSV file the user chooses.
    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "EffiLens-time-\(viewModel.period.rawValue.lowercased()).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        func esc(_ s: String) -> String { "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" }
        let iso = ISO8601DateFormatter()
        var csv = "task,project,started_at,ended_at,duration_sec,manual\n"
        for log in sessions {
            csv += [esc(log.taskName), esc(log.projectName), iso.string(from: log.startedAt), iso.string(from: log.endedAt), "\(log.durationSec)", log.isManual ? "true" : "false"].joined(separator: ",") + "\n"
        }
        do { try csv.write(to: url, atomically: true, encoding: .utf8); exportError = nil } catch { exportError = "Couldn't save the file." }
    }
}

// MARK: - Manual entry (prototype V.manual; POST /task-time/manual — admin+)

struct ManualEntryView: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator
    @State private var work: AssignedWorkModel
    @State private var selectedTask: UUID?
    @State private var day = Date()
    @State private var start = Calendar.current.date(byAdding: .hour, value: -1, to: Date()) ?? Date()
    @State private var end = Date()
    @State private var submitting = false
    @State private var result: Result<ManualTimeLogOut, AppError>?
    private let service: WorkService

    init(environment: AppEnvironment) {
        _work = State(initialValue: AssignedWorkModel(environment: environment))
        service = environment.work
    }

    private var choices: [TaskChoice] { TaskChoice.all(work.projects.value ?? []) }

    private func combine(_ day: Date, _ time: Date) -> Date {
        let cal = Calendar.current
        let d = cal.dateComponents([.year, .month, .day], from: day)
        let t = cal.dateComponents([.hour, .minute], from: time)
        return cal.date(from: DateComponents(year: d.year, month: d.month, day: d.day, hour: t.hour, minute: t.minute)) ?? time
    }

    private var startedAt: Date { combine(day, start) }
    private var endedAt: Date { combine(day, end) }

    private var validationMessage: String? {
        if selectedTask == nil { return "Choose a task." }
        if endedAt <= startedAt { return "End time must be after start time." }
        if endedAt > Date() { return "Entries can't be in the future." }
        return nil
    }

    var body: some View {
        Page {
            FractionalColumns(ratio: 1.2) {
                Card("New time entry") {
                    VStack(alignment: .leading, spacing: 0) {
                        FieldLabel("Task").padding(.top, -12)
                        FieldChrome {
                            Picker("Task", selection: $selectedTask) {
                                Text("Choose…").tag(UUID?.none)
                                ForEach(choices) { Text("\($0.task.name) — \($0.project.name)").tag(Optional($0.task.id)) }
                            }
                            .pickerStyle(.menu)
                            .buttonStyle(.plain)
                        }
                        EqualColumns(count: 3, spacing: 10) {
                            VStack(alignment: .leading, spacing: 0) {
                                FieldLabel("Date")
                                FieldChrome { DatePicker("Date", selection: $day, in: ...Date(), displayedComponents: .date).datePickerStyle(.field) }
                            }
                            VStack(alignment: .leading, spacing: 0) {
                                FieldLabel("Start")
                                FieldChrome { DatePicker("Start", selection: $start, displayedComponents: .hourAndMinute).datePickerStyle(.field) }
                            }
                            VStack(alignment: .leading, spacing: 0) {
                                FieldLabel("End")
                                FieldChrome { DatePicker("End", selection: $end, displayedComponents: .hourAndMinute).datePickerStyle(.field) }
                            }
                        }
                        HStack {
                            Text("Duration").font(Typo.label).foregroundStyle(Palette.textSecondary)
                            Spacer()
                            Text(Format.duration(Int(max(0, endedAt.timeIntervalSince(startedAt))))).font(Typo.mono)
                        }
                        .padding(.top, 12)
                        Group {
                            if case .failure(let error) = result { Text(error.userMessage).foregroundStyle(Palette.danger) }
                            else if case .success(let log) = result { Text("Saved \(Format.duration(log.durationSec)) on \(log.taskName ?? "task").").foregroundStyle(Palette.success) }
                            else if let validationMessage { Text(validationMessage).foregroundStyle(Palette.textTertiary) }
                        }
                        .font(.system(size: 12))
                        .padding(.top, 10)
                        HStack {
                            Spacer()
                            Button("Cancel") { navigator.go(.history) }.buttonStyle(.effi)
                            Button {
                                Task { await submit() }
                            } label: {
                                HStack(spacing: 6) {
                                    if submitting { ProgressView().controlSize(.small) }
                                    Text("Save Entry")
                                }
                            }
                            .buttonStyle(.effiPrimary)
                            .disabled(validationMessage != nil || submitting)
                        }
                        .padding(.top, 14)
                    }
                }
                Card("Policy", symbol: "info.circle") {
                    Text("Manual entries can be added by administrators only and are recorded against **\(model.user?.displayName ?? "your account")** with your name as the creator. The server rejects overlapping or future entries. Employee self-service entries with manager approval are not available yet.")
                        .font(Typo.body).foregroundStyle(Palette.textSecondary).lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .task { await work.load() }
    }

    private func submit() async {
        guard let user = model.user, let taskId = selectedTask,
              let choice = choices.first(where: { $0.task.id == taskId }) else { return }
        submitting = true
        defer { submitting = false }
        let body = ManualTimeLogCreate(userId: user.id, taskId: taskId, projectId: choice.project.id,
                                       startedAt: startedAt, endedAt: endedAt, timezone: TimeZone.current.identifier)
        do { result = .success(try await service.createManualLog(body)) }
        catch { result = .failure(DashboardViewModel.map(error)) }
    }
}
