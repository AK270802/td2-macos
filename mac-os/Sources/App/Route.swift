import Foundation
import EffiLensKit

/// Sidebar destinations — structure follows the prototype's navigation
/// (Dashboard · Time Tracking · Leave Management · Workspace).
enum Route: String, Hashable, CaseIterable, Identifiable {
    case dashboard
    // Time tracking
    case tracker, projects, tasks, history, manualEntry
    // Leave management
    case leaveOverview, applyLeave, myRequests, leaveCalendar, leaveBalance, holidays
    // Workspace
    case team, approvals, reports, notifications, activity, settings, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .tracker: return "Time Tracker"
        case .projects: return "Projects"
        case .tasks: return "Assigned Tasks"
        case .history: return "Time History"
        case .manualEntry: return "Manual Entry"
        case .leaveOverview: return "Leave Overview"
        case .applyLeave: return "Apply for Leave"
        case .myRequests: return "My Requests"
        case .leaveCalendar: return "Leave Calendar"
        case .leaveBalance: return "Leave Balance"
        case .holidays: return "Holidays"
        case .team: return "Team"
        case .approvals: return "Approvals"
        case .reports: return "Reports"
        case .notifications: return "Notifications"
        case .activity: return "Activity"
        case .settings: return "Settings"
        case .about: return "About & Diagnostics"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .tracker: return "timer"
        case .projects: return "folder"
        case .tasks: return "checklist"
        case .history: return "clock.arrow.circlepath"
        case .manualEntry: return "square.and.pencil"
        case .leaveOverview: return "calendar.badge.clock"
        case .applyLeave: return "plus.circle"
        case .myRequests: return "tray.full"
        case .leaveCalendar: return "calendar"
        case .leaveBalance: return "chart.pie"
        case .holidays: return "sun.max"
        case .team: return "person.2"
        case .approvals: return "checkmark.seal"
        case .reports: return "chart.bar.xaxis"
        case .notifications: return "bell"
        case .activity: return "list.bullet.rectangle"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        }
    }

    /// Minimum role, mirroring the backend dependency guarding the route's
    /// primary endpoint (verified in core-services/app/api/v1):
    /// - Approvals → manager-approve requires manager+.
    /// - Team → /dashboard/team requires manager+.
    /// - Reports → /reports requires manager+.
    /// - Manual Entry → POST /task-time/manual requires admin+.
    var minimumRole: UserRole {
        switch self {
        case .approvals, .team, .reports: return .manager
        case .manualEntry: return .admin
        default: return .user
        }
    }

    /// Settings and About open in their own scenes on macOS but remain reachable from the sidebar.
    static let sections: [SidebarSection] = [
        SidebarSection(title: nil, routes: [.dashboard]),
        SidebarSection(title: "Time Tracking", routes: [.tracker, .projects, .tasks, .history, .manualEntry]),
        SidebarSection(title: "Leave Management", routes: [.leaveOverview, .applyLeave, .myRequests, .leaveCalendar, .leaveBalance, .holidays]),
        SidebarSection(title: "Workspace", routes: [.team, .approvals, .reports, .notifications, .activity, .settings, .about]),
    ]
}

struct SidebarSection: Identifiable {
    let title: String?
    let routes: [Route]
    var id: String { title ?? "_root" }
}
