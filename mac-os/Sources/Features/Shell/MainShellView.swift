import SwiftUI
import EffiLensKit

/// Main window: native NavigationSplitView with the prototype's sidebar
/// structure and toolbar (sync state · bell · Apply Leave).
struct MainShellView: View {
    @Environment(AppModel.self) private var model
    @SceneStorage("effilens.route") private var storedRoute: String = Route.dashboard.rawValue
    @State private var selection: Route? = .dashboard

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 210, ideal: 228, max: 280)
        } detail: {
            detail(for: selection ?? .dashboard)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Palette.canvas)
                .navigationTitle((selection ?? .dashboard).title)
                .toolbar { ShellToolbar(unread: model.unreadNotifications, selection: $selection) }
        }
        .onAppear {
            if let restored = Route(rawValue: storedRoute), model.role.atLeast(restored.minimumRole) { selection = restored }
        }
        .onChange(of: selection) { _, newValue in
            if let newValue { storedRoute = newValue.rawValue }
        }
    }

    @ViewBuilder
    private func detail(for route: Route) -> some View {
        if let environment = model.environment {
            switch route {
            case .dashboard:
                DashboardView(environment: environment, onNavigate: { selection = $0 })
            case .leaveOverview:
                LeaveOverviewView(environment: environment, onNavigate: { selection = $0 })
            default:
                ScheduledScreenView(route: route)
            }
        }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: Route?

    var body: some View {
        List(selection: $selection) {
            ForEach(Route.sections) { section in
                let visible = section.routes.filter { model.role.atLeast($0.minimumRole) }
                if !visible.isEmpty {
                    if let title = section.title {
                        Section(title) { rows(visible) }
                    } else {
                        rows(visible)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { userCard }
    }

    @ViewBuilder
    private func rows(_ routes: [Route]) -> some View {
        ForEach(routes) { route in
            Label(route.title, systemImage: route.symbol)
                .badge(badge(for: route))
                .tag(route)
        }
    }

    private func badge(for route: Route) -> Int {
        route == .notifications ? model.unreadNotifications : 0
    }

    private var userCard: some View {
        HStack(spacing: Space.s) {
            InitialsAvatar(initials: model.user?.initials ?? "?")
            VStack(alignment: .leading, spacing: 0) {
                Text(model.user?.displayName ?? "")
                    .font(Typo.bodyEmphasis)
                    .lineLimit(1)
                trackingStatus
            }
            Spacer(minLength: 0)
            Menu {
                if let org = model.user?.organizationName { Text(org) }
                Divider()
                Button("Sign Out") { Task { await model.signOut() } }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Account menu")
        }
        .padding(Space.m)
        .background(.bar)
    }

    @ViewBuilder
    private var trackingStatus: some View {
        switch model.agentLink {
        case .connected(let state) where state.state == .running:
            Label("Tracking", systemImage: "circle.fill").foregroundStyle(Palette.success)
        case .connected(let state) where state.state == .onBreak:
            Label("On break", systemImage: "circle.fill").foregroundStyle(Palette.warning)
        case .connected:
            Label("Available", systemImage: "circle").foregroundStyle(Palette.textSecondary)
        case .legacyConflict:
            Label("Legacy app running", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning)
        case .unavailable, .unknown:
            Label("Agent offline", systemImage: "circle.dashed").foregroundStyle(Palette.textTertiary)
        }
    }
}

struct ShellToolbar: ToolbarContent {
    let unread: Int
    @Binding var selection: Route?

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            SyncIndicator()
            Button {
                selection = .notifications
            } label: {
                Image(systemName: unread > 0 ? "bell.badge" : "bell")
            }
            .help("Notifications")
            .accessibilityLabel(unread > 0 ? "Notifications, \(unread) unread" : "Notifications")

            Button {
                selection = .applyLeave
            } label: {
                Label("Apply Leave", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .help("Apply for leave (⌘N)")
            .keyboardShortcut("n", modifiers: .command)
        }
    }
}

/// Toolbar sync pill — reflects the local agent's real queue state.
struct SyncIndicator: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.agentLink {
        case .connected:
            if let sync = model.syncStatus {
                if sync.connected {
                    StatusPill(text: sync.lastSync.map { "Synced · \(Format.relative($0))" } ?? "Connected", tone: .success)
                } else {
                    StatusPill(text: "Offline · \(sync.pendingEvents) pending", tone: .danger)
                }
            } else {
                StatusPill(text: "Connected", tone: .success)
            }
        case .legacyConflict:
            StatusPill(text: "Legacy agent running", tone: .warning)
                .help("Quit the older EffiLens app to enable tracking here. Running both would record time twice.")
        case .unavailable, .unknown:
            StatusPill(text: "Agent offline", tone: .neutral)
                .help("The EffiLens tracking agent is not running. Time tracking is unavailable; everything else works.")
        }
    }
}
