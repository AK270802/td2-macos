import SwiftUI
import UserNotifications
import EffiLensKit

/// Six-step first-run onboarding inside the app (distinct from the DMG/PKG
/// installer): 1 Welcome · 2 Sign in · 3 Consent · 4 Permissions ·
/// 5 Background agent · 6 Ready. Steps 2–3 are the existing sign-in and
/// server-tracked consent screens.
struct OnboardingStepIndicator: View {
    let current: Int
    private let titles = ["Welcome", "Sign in", "Consent", "Permissions", "Background", "Ready"]

    var body: some View {
        HStack(spacing: Space.s) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                HStack(spacing: Space.xs) {
                    Circle()
                        .fill(index + 1 <= current ? Palette.accent : Palette.divider)
                        .frame(width: 8, height: 8)
                    Text(title).font(Typo.caption)
                        .foregroundStyle(index + 1 == current ? Palette.textPrimary : Palette.textTertiary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current) of 6")
    }
}

struct WelcomeView: View {
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: Space.xl) {
            OnboardingStepIndicator(current: 1)
            Image("BrandLockup").resizable().interpolation(.high).scaledToFit().frame(height: 90).accessibilityLabel("EffiLens")
            Text("Welcome to EffiLens").font(Typo.display)
            VStack(alignment: .leading, spacing: Space.m) {
                Label("Track time on your assigned tasks — you start and stop the timer.", systemImage: "timer")
                Label("Apply for leave and follow approvals.", systemImage: "calendar")
                Label("Only counts and window-level information are captured, and only while you track.", systemImage: "lock.shield")
            }
            .font(Typo.body)
            .frame(maxWidth: 460, alignment: .leading)
            Button("Get Started", action: onContinue)
                .buttonStyle(.borderedProminent).controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Steps 4–6, shown once after consent.
struct SetupFlowView: View {
    @Environment(AppModel.self) private var model
    @State private var step = 4
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    var onFinish: () -> Void

    var body: some View {
        VStack(spacing: Space.l) {
            OnboardingStepIndicator(current: step)
            Group {
                switch step {
                case 4: permissions
                case 5: background
                default: ready
                }
            }
            .frame(maxWidth: 620)
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { notificationStatus = await DesktopNotifier.authorizationStatus() }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            PermissionsView(onDone: nil)
            HStack(spacing: Space.m) {
                Image(systemName: "bell.badge").foregroundStyle(Palette.accent).frame(width: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Notifications").font(Typo.bodyEmphasis)
                    Text("Tracking reminders, idle warnings and leave updates.").font(Typo.caption).foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                if notificationStatus == .authorized {
                    StatusPill(text: "Allowed", tone: .success)
                } else {
                    Button("Allow…") {
                        Task {
                            await DesktopNotifier.requestAuthorization()
                            notificationStatus = await DesktopNotifier.authorizationStatus()
                        }
                    }
                }
            }
            .padding(Space.m)
            HStack(spacing: Space.m) {
                Image(systemName: "globe").foregroundStyle(Palette.accent).frame(width: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Automation (browsers)").font(Typo.bodyEmphasis)
                    Text("macOS asks the first time EffiLens reads the active tab's domain. Only the domain (e.g. example.com) is kept.")
                        .font(Typo.caption).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Open Settings…") { LocalPermissions.openSettings(pane: "Privacy_Automation") }
            }
            .padding(Space.m)
            HStack {
                Text("You can skip any permission; EffiLens then runs with reduced tracking.").font(Typo.caption).foregroundStyle(Palette.textSecondary)
                Spacer()
                Button("Continue") { step = 5 }.buttonStyle(.borderedProminent)
            }
        }
    }

    private var background: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Background tracking agent").font(Typo.title)
            Text("EffiLens uses a small background agent so tracking keeps working when the window is closed. It never records unless you are tracking a task.")
                .font(Typo.body).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Status").foregroundStyle(Palette.textSecondary)
                Spacer()
                switch model.agentRegistration {
                case .enabled: StatusPill(text: model.isAgentConnected ? "Running" : "Starting…", tone: model.isAgentConnected ? .success : .info)
                case .requiresApproval: StatusPill(text: "Needs approval", tone: .warning)
                case .notBundled: StatusPill(text: "Not in this build", tone: .danger)
                case .failed: StatusPill(text: "Failed", tone: .danger)
                case .none: StatusPill(text: "Not registered", tone: .neutral)
                }
            }
            if model.agentRegistration == .requiresApproval {
                Text("Open System Settings › General › Login Items and switch on EffiLens under “Allow in the Background”.")
                    .font(Typo.caption).fixedSize(horizontal: false, vertical: true)
                Button("Open Login Items…") { AgentLifecycle.openLoginItemsSettings() }
            }
            HStack {
                Button("Back") { step = 4 }
                Button("Check Again") { model.restartAgentConnection() }
                Spacer()
                Button("Continue") { step = 6 }.buttonStyle(.borderedProminent)
            }
        }
    }

    private var ready: some View {
        VStack(spacing: Space.l) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(Palette.success)
            Text("You're all set").font(Typo.title)
            Text("Pick a task in Time Tracker to start. The menu bar timer lets you pause or stop at any time.")
                .font(Typo.body).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center)
            Button("Open EffiLens", action: onFinish).buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
        }
    }
}
