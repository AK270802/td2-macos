import SwiftUI

/// Honest placeholder for prototype screens not yet implemented. Shows which
/// milestone delivers the screen — never mock data (IMPLEMENTATION_PLAN.md).
struct ScheduledScreenView: View {
    let route: Route

    private var milestone: String {
        switch route {
        case .tracker, .projects, .tasks, .history, .manualEntry, .notifications, .activity, .team:
            return "Milestone 4 — Core application screens"
        case .applyLeave, .myRequests, .leaveCalendar, .leaveBalance, .holidays, .approvals:
            return "Milestone 5 — Leave management"
        case .reports:
            return "Milestone 6 — Reports and analytics"
        case .settings, .about:
            return "Milestone 7 — macOS application experience"
        case .dashboard, .leaveOverview:
            return ""
        }
    }

    var body: some View {
        ContentUnavailableView {
            Label(route.title, systemImage: route.symbol)
        } description: {
            Text("This screen is scheduled for \(milestone).")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
