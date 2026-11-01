import SwiftUI
import Observation
import EffiLensKit

/// In-window navigation state: the sidebar route plus prototype "detail"
/// pages (request details, team member) that replace the content with a
/// back button rather than opening a sheet.
@MainActor
@Observable
final class Navigator {
    var route: Route = .dashboard {
        didSet { if oldValue != route { leaveDetail = nil; member = nil } }
    }
    var leaveDetail: LeaveDetailContext?
    var member: MemberContext?
    /// Project filter handed from Projects → Tasks ("View Tasks").
    var taskProjectFilter: UUID?

    func go(_ route: Route) { self.route = route }
}

struct LeaveDetailContext: Equatable {
    let application: LeaveApplication
    let mode: LeaveDetailView.Mode
    let back: Route
}

struct MemberContext: Equatable {
    let member: UserTimeItem
    let period: ReportPeriod
}

/// Main window (prototype `#app`): 228 pt sidebar + main column with a
/// 52 pt toolbar band. The window uses a hidden title bar so the traffic
/// lights sit over the sidebar exactly as in the prototype.
struct MainShellView: View {
    @Environment(AppModel.self) private var model
    @SceneStorage("effilens.route") private var storedRoute: String = Route.dashboard.rawValue
    @State private var navigator = Navigator()
    /// Forces the first route (visual review); otherwise the last route is restored.
    var initialRoute: Route?

    var body: some View {
        HStack(spacing: 0) {
            EffiSidebar()
                .frame(width: Metrics.sidebarWidth)
            Divider().overlay(Palette.hairline)
            VStack(spacing: 0) {
                ShellHeader()
                Divider().overlay(Palette.hairline)
                OfflineBanner()
                PermissionsBanner()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background(Palette.canvas)
        }
        .background(GlassBackdrop())
        .environment(navigator)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            if let initialRoute { navigator.route = initialRoute; return }
            if let restored = Route(rawValue: storedRoute), model.role.atLeast(restored.minimumRole) { navigator.route = restored }
        }
        .onChange(of: navigator.route) { _, newValue in storedRoute = newValue.rawValue }
        .onChange(of: model.requestedRoute) { _, route in
            if let route { navigator.go(route); model.requestedRoute = nil }
        }
        .sheet(isPresented: Binding(get: { model.idleWarningStartedAt != nil }, set: { _ in })) {
            if let startedAt = model.idleWarningStartedAt {
                IdleWarningSheet(startedAt: startedAt)
            }
        }
        .alert(
            "Tracking agent",
            isPresented: Binding(get: { model.agentCommandError != nil }, set: { if !$0 { model.agentCommandError = nil } }),
            presenting: model.agentCommandError
        ) { _ in
            Button("Reconnect") { model.restartAgentConnection() }
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.userMessage)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let environment = model.environment {
            Group {
                if let context = navigator.leaveDetail {
                    LeaveDetailView(application: context.application, environment: environment, mode: context.mode) {
                        navigator.leaveDetail = nil
                    }
                } else if let context = navigator.member {
                    MemberDetailView(member: context.member, period: context.period, environment: environment)
                } else {
                    screen(navigator.route, environment: environment)
                }
            }
            .id(navigator.route.rawValue + (navigator.leaveDetail?.application.id.uuidString ?? "") + (navigator.member?.member.id.uuidString ?? ""))
        }
    }

    @ViewBuilder
    private func screen(_ route: Route, environment: AppEnvironment) -> some View {
        switch route {
        case .dashboard: DashboardView(environment: environment, onNavigate: { navigator.go($0) })
        case .tracker: TrackerView(environment: environment)
        case .projects: ProjectsView(environment: environment)
        case .tasks: TasksView(environment: environment)
        case .history: HistoryView(environment: environment)
        case .manualEntry: ManualEntryView(environment: environment)
        case .leaveOverview: LeaveOverviewView(environment: environment, onNavigate: { navigator.go($0) })
        case .applyLeave: ApplyLeaveView(environment: environment, onNavigate: { navigator.go($0) })
        case .myRequests: LeaveRequestsView(environment: environment, ownUserId: model.user?.id)
        case .leaveCalendar: LeaveCalendarView(environment: environment)
        case .leaveBalance: LeaveBalanceView(environment: environment)
        case .holidays: HolidaysView(environment: environment)
        case .team: TeamView(environment: environment)
        case .approvals: ApprovalsView(environment: environment, me: model.user?.id, role: model.role)
        case .reports: ReportsView(environment: environment)
        case .notifications: NotificationsView(environment: environment)
        case .activity: ActivityView(environment: environment)
        case .settings: SettingsRootView()
        case .about: AboutDiagnosticsView()
        }
    }
}

// MARK: - Sidebar (prototype .sidebar)

struct EffiSidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator
    @State private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    searchField
                    ForEach(Route.sections) { section in
                        let visible = section.routes.filter { model.role.atLeast($0.minimumRole) }
                        if !visible.isEmpty {
                            if let title = section.title {
                                Text(title).font(Typo.overline).foregroundStyle(Palette.textTertiary)
                                    .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 4)
                            }
                            ForEach(visible) { route in row(route) }
                        }
                    }
                }
                .padding(.top, 46)
                .padding(.horizontal, 10)
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 6) {
                    BrandLogoTile(size: 20)
                    Text("EffiLens").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.textSecondary)
                }
                .padding(.leading, 84)
                .padding(.top, 10)
                .allowsHitTesting(false)
            }
            .scrollIndicators(.never)
            userCard
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
                .padding(.top, 6)
        }
        .background(Palette.sidebar)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
            TextField("Search", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .onSubmit {
                    navigator.taskProjectFilter = nil
                    navigator.go(.tasks)
                }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(Palette.textPrimary.opacity(0.07), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .padding(.horizontal, 4)
        .padding(.bottom, 12)
    }

    private func isSelected(_ route: Route) -> Bool {
        if navigator.route == route { return true }
        return false
    }

    private func row(_ route: Route) -> some View {
        let selected = isSelected(route)
        return Button {
            navigator.go(route)
        } label: {
            HStack(spacing: 9) {
                if !route.isSubItem {
                    Image(systemName: route.symbol)
                        .font(.system(size: 13, weight: .regular))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(Palette.accent)
                        .frame(width: 16)
                }
                Text(route.title)
                    .font(.system(size: 13, weight: route.isSubItem ? .regular : .medium))
                    .foregroundStyle(route.isSubItem && !selected ? Palette.textSecondary : Palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                badge(for: route)
            }
            .padding(.vertical, 5)
            .padding(.leading, route.isSubItem ? 35 : 10)
            .padding(.trailing, 10)
            .background(selected ? Palette.accentSoft : .clear, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(SidebarRowButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func badge(for route: Route) -> some View {
        if route == .notifications, model.unreadNotifications > 0 {
            Text("\(model.unreadNotifications)")
                .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 6).background(Palette.redFill, in: Capsule())
        }
    }

    private var userCard: some View {
        Button {
            UserDefaults.standard.set(SettingsRootView.Pane.account.rawValue, forKey: "effilens.settings.pane")
            navigator.go(.settings)
        } label: {
            HStack(spacing: 9) {
                InitialsAvatar(initials: model.user?.initials ?? "?", size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.user?.displayName ?? "Not signed in").font(.system(size: 12.5, weight: .bold)).foregroundStyle(Palette.textPrimary).lineLimit(1)
                    trackingStatus.font(.system(size: 11))
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Palette.textPrimary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let org = model.user?.organizationName { Text(org) }
            Button("Account Settings…") { navigator.go(.settings) }
            Divider()
            Button("Sign Out") { Task { await model.signOut() } }
        }
        .help("Account — right-click for Sign Out")
        .accessibilityLabel("Account")
    }

    @ViewBuilder
    private var trackingStatus: some View {
        switch model.agentLink {
        case .connected(let state) where state.state == .running:
            Text("● Tracking").foregroundStyle(Palette.success)
        case .connected(let state) where state.state == .onBreak:
            Text("● On break").foregroundStyle(Palette.warning)
        case .connected:
            Text("● Available").foregroundStyle(Palette.textTertiary)
        case .legacyConflict:
            Text("● Legacy app running").foregroundStyle(Palette.warning)
        case .unavailable, .unknown:
            Text("● Agent offline").foregroundStyle(Palette.textTertiary)
        }
    }
}

private struct SidebarRowButtonStyle: ButtonStyle {
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(hovering ? Palette.textPrimary.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .onHover { hovering = $0 }
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

// MARK: - Toolbar band (prototype .toolbar)

struct ShellHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator
    @Environment(\.openWindow) private var openWindow

    private var titles: (String, String) {
        if let detail = navigator.leaveDetail { return ("Request Details", Format.dateRange(detail.application.startDate, detail.application.endDate)) }
        if let member = navigator.member { return ("Team Member", member.member.displayName) }
        return (navigator.route.toolbarTitle, navigator.route.toolbarSubtitle)
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(titles.0).font(Typo.toolbarTitle).foregroundStyle(Palette.textPrimary)
                if !titles.1.isEmpty { Text(titles.1).font(.system(size: 12)).foregroundStyle(Palette.textTertiary) }
            }
            Spacer()
            SyncIndicator()
            MiniTimerToolbarButton { openWindow(id: SceneID.miniTimer) }
            ToolbarIconButton(symbol: "bell", help: model.unreadNotifications > 0 ? "Notifications, \(model.unreadNotifications) unread" : "Notifications",
                              showsPip: model.unreadNotifications > 0) { navigator.go(.notifications) }
            Button("+ Apply Leave") { navigator.go(.applyLeave) }
                .buttonStyle(.effiPrimary)
                .keyboardShortcut("n", modifiers: .command)
                .help("Apply for leave (⌘N)")
        }
        .padding(.horizontal, 18)
        .frame(height: Metrics.toolbarHeight)
        .background(Palette.toolbar)
    }
}

/// Sync pill (`.sync` / `.sync.off`) — reflects the agent's real queue.
struct SyncIndicator: View {
    @Environment(AppModel.self) private var model

    private var state: (text: String, ok: Bool, help: String) {
        switch model.agentLink {
        case .connected:
            if let sync = model.syncStatus {
                if sync.connected {
                    return (sync.lastSync.map { "Synced · \(Format.relative($0))" } ?? "Connected", true, "Activity is syncing to the server.")
                }
                return ("Offline · \(sync.pendingEvents) pending", false, "Activity is saved on this Mac and syncs when the connection returns.")
            }
            return ("Connected", true, "Tracking agent connected.")
        case .legacyConflict:
            return ("Legacy agent running", false, "Quit the older WorkPulse app to enable tracking here.")
        case .unavailable, .unknown:
            return ("Agent offline", false, "The EffiLens tracking agent is not running. Tracking is unavailable; everything else works.")
        }
    }

    var body: some View {
        let s = state
        HStack(spacing: 6) {
            Circle().fill(s.ok ? Palette.okFill : Palette.redFill).frame(width: 6, height: 6)
            Text(s.text).font(.system(size: 11.5)).foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background((s.ok ? Palette.okFill : Palette.redFill).opacity(0.10), in: Capsule())
        .overlay(Capsule().strokeBorder((s.ok ? Palette.okFill : Palette.redFill).opacity(0.28)))
        .help(s.help)
        .accessibilityElement(children: .combine)
    }
}

/// Prototype `.offline-banner`.
struct OfflineBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let sync = model.syncStatus, !sync.connected, model.isAgentConnected {
            HStack(spacing: Space.m) {
                Text("⚠︎ You're offline. Tracking continues locally — \(sync.pendingEvents) record(s) waiting to sync.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.danger)
                Spacer()
                Button("Reconnect") { Task { await model.runAgent { try await $0.syncNow() } } }
                    .buttonStyle(.effi)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 9)
            .background(Palette.redFill.opacity(0.12))
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.redFill.opacity(0.3)).frame(height: 1) }
        }
    }
}

/// Prototype mini-timer toolbar glyph: a rounded capsule with a dot.
struct MiniTimerToolbarButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .leading) {
                Capsule().strokeBorder(Palette.textSecondary, lineWidth: 1.6).frame(width: 18, height: 10)
                Circle().fill(Palette.textSecondary).frame(width: 3.5, height: 3.5).padding(.leading, 3.5)
            }
            .frame(width: 30, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Mini timer (⇧⌘M)")
        .accessibilityLabel("Mini timer")
    }
}
