import AppKit
import Foundation
import UserNotifications
import ServiceManagement
import EffiLensKit

/// User preferences stored locally (per Mac). Nothing here is sent to the
/// backend; server-side settings (screenshot interval, idle threshold …) are
/// owned by the organisation and shown read-only.
enum Prefs {
    static let desktopNotifications = "effilens.prefs.desktopNotifications"
    static let dockBadge = "effilens.prefs.dockBadge"
    static let appearance = "effilens.prefs.appearance"          // system | light | dark
    static let menuBarTimer = "effilens.prefs.menuBarTimer"
    static let confirmQuitWhileTracking = "effilens.prefs.confirmQuit"
    /// go-agent `notification_interval_min`: 0 = never; default 15.
    static let reminderInterval = "effilens.prefs.reminderIntervalMin"

    static var reminderIntervalMin: Int {
        UserDefaults.standard.object(forKey: reminderInterval) == nil ? 15 : UserDefaults.standard.integer(forKey: reminderInterval)
    }

    static func bool(_ key: String, default value: Bool = true) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil ? value : UserDefaults.standard.bool(forKey: key)
    }
}

/// Local macOS notifications + Dock badge. Notification content never includes
/// tokens or personal data beyond what the user already sees in the app.
@MainActor
enum DesktopNotifier {
    static func updateDockBadge(_ unread: Int) {
        let show = Prefs.bool(Prefs.dockBadge) && unread > 0
        NSApp?.dockTile.badgeLabel = show ? (unread > 99 ? "99+" : "\(unread)") : nil
    }

    /// Current authorisation (`.notDetermined` until the user is asked).
    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Asks once; the system remembers the answer. Returns whether granted.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }

    static func postUnreadSummary(newCount: Int) async {
        guard Prefs.bool(Prefs.desktopNotifications) else { return }
        guard await authorizationStatus() == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "EffiLens"
        content.body = newCount == 1 ? "You have a new notification." : "You have \(newCount) new notifications."
        content.threadIdentifier = "effilens.notifications"
        let request = UNNotificationRequest(identifier: "unread-\(Date().timeIntervalSince1970)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Same wording as the go-agent "tracker inactive" reminder.
    static func postInactiveReminder() async {
        guard await authorizationStatus() == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Effilens Tracker Inactive"
        content.body = "Task tracking is currently OFF. Please select an assigned task and start tracking."
        content.threadIdentifier = "effilens.reminder"
        let request = UNNotificationRequest(identifier: "inactive-reminder", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func postIdleWarning() async {
        guard Prefs.bool(Prefs.desktopNotifications) else { return }
        guard await authorizationStatus() == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Are you still working?"
        content.body = "EffiLens noticed no activity. Open EffiLens to keep or discard the idle time."
        content.threadIdentifier = "effilens.idle"
        let request = UNNotificationRequest(identifier: "idle-warning", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

/// Quit-while-tracking confirmation. Quitting the app does NOT stop the
/// background agent (launchd keeps it running), so the user chooses between
/// keeping tracking in the background or stopping first.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, Prefs.bool(Prefs.confirmQuitWhileTracking),
              let state = model.timerState, state.state == .running || state.state == .onBreak else {
            return .terminateNow
        }
        let alert = NSAlert()
        alert.messageText = "EffiLens is tracking time"
        alert.informativeText = "“\(state.task?.taskName ?? "Current task")” is being tracked. The background agent keeps tracking after you quit the app unless you stop it."
        alert.addButton(withTitle: "Keep Tracking & Quit")
        alert.addButton(withTitle: "Stop Tracking & Quit")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(false, forKey: Prefs.confirmQuitWhileTracking)
        }
        switch response {
        case .alertFirstButtonReturn:
            return .terminateNow
        case .alertSecondButtonReturn:
            Task { @MainActor in
                await model.runAgent { try await $0.stopTracking() }
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        default:
            return .terminateCancel
        }
    }
}

/// "Launch at startup" for the app itself (go-agent `autostart`). The
/// tracking agent has its own LaunchAgent registration (AgentLifecycle).
@MainActor
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns a user-facing error, or nil on success.
    static func set(enabled: Bool) -> String? {
        do {
            if enabled, SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            if !enabled, SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return "Couldn't change launch at startup: \(error.localizedDescription)"
        }
    }
}

/// go-agent parity (internal/engine/notifier.go): while signed in but not
/// tracking, remind every N minutes after tracking stopped. N = 0 disables.
@MainActor
final class InactiveReminder {
    private var stoppedAt: Date?
    private var lastNotified: Date?

    func update(isTracking: Bool, now: Date = Date()) async {
        if isTracking {
            stoppedAt = nil
            return
        }
        if stoppedAt == nil { stoppedAt = now }
        let minutes = Prefs.reminderIntervalMin
        guard minutes > 0, let stoppedAt else { return }
        let required = TimeInterval(minutes * 60)
        guard now.timeIntervalSince(stoppedAt) >= required else { return }
        if let lastNotified, lastNotified >= stoppedAt, now.timeIntervalSince(lastNotified) < required { return }
        lastNotified = now
        await DesktopNotifier.postInactiveReminder()
    }
}
