import AppKit
import SwiftUI
import EffiLensKit

/// Routes between the onboarding window (prototype `#onboard`, 820 × 560,
/// four steps) and the main window (prototype `#app`, 1200 × 780).
struct RootView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("effilens.onboarding.setupDone") private var setupDone = false

    private enum Mode: Equatable { case onboarding, main }

    private var mode: Mode {
        switch model.phase {
        case .ready: return setupDone ? .main : .onboarding
        case .launching, .configurationError: return setupDone ? .main : .onboarding
        default: return .onboarding
        }
    }

    var body: some View {
        Group {
            switch model.phase {
            case .launching:
                LaunchView()
            case .signedOut:
                SignInView()
            case .consentRequired:
                PostSignInOnboarding(step: setupDone ? .privacy : .setup) { setupDone = true }
            case .passwordChangeRequired:
                OnboardingWindow { PasswordChangeRequiredView() }
            case .ready:
                if setupDone {
                    MainShellView()
                } else {
                    PostSignInOnboarding(step: .setup) { setupDone = true }
                }
            case .configurationError(let message):
                OnboardingWindow {
                    OnboardingHeading(prefix: "EffiLens can’t ", emphasis: "start", subtitle: message)
                }
            }
        }
        .background(Palette.canvas)
        .background(WindowConfigurator(onboarding: mode == .onboarding))
        .animation(Motion.quick, value: model.phase)
        .onChange(of: model.phase) { _, phase in
            // A new account (or a sign-out) repeats setup on next sign-in.
            if phase == .signedOut { setupDone = false }
        }
    }
}

/// Sizes the hosting window: fixed 820 × 560 for onboarding (as in the
/// prototype), resizable 1200 × 780 (min 1000 × 560) for the main app.
struct WindowConfigurator: NSViewRepresentable {
    let onboarding: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let onboarding = self.onboarding
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = onboarding
            let target = onboarding ? Metrics.onboardingWindow : Metrics.mainWindow
            let minimum = onboarding ? Metrics.onboardingWindow : Metrics.mainWindowMin
            if onboarding {
                window.styleMask.remove(.resizable)
            } else {
                window.styleMask.insert(.resizable)
            }
            window.contentMinSize = minimum
            window.contentMaxSize = onboarding ? Metrics.onboardingWindow : CGSize(width: 10_000, height: 10_000)
            let current = window.contentRect(forFrameRect: window.frame).size
            let needsResize = onboarding ? current != target : (current.width < minimum.width || current.height < minimum.height || context.coordinator.lastOnboarding == true)
            if needsResize {
                window.setContentSize(target)
                window.center()
            }
            context.coordinator.lastOnboarding = onboarding
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var lastOnboarding: Bool? }
}

private struct LaunchView: View {
    var body: some View {
        VStack(spacing: Space.l) {
            AppIconTile(size: 72)
            ProgressView().controlSize(.small).tint(Palette.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Starting EffiLens")
    }
}

/// The backend blocks portal APIs until the password is changed (403 +
/// X-Password-Change-Required); the user is directed to the portal.
private struct PasswordChangeRequiredView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingHeading(prefix: "Change your ", emphasis: "password", subtitle: AppError.passwordChangeRequired.userMessage)
            Spacer()
            HStack {
                Spacer()
                Button("Sign Out") { Task { await model.signOut() } }.buttonStyle(.effi)
                if let portal = model.environment?.configuration.portalOrigin {
                    Button("Change Password in Portal") { NSWorkspace.shared.open(portal.appending(path: "change-password")) }
                        .buttonStyle(.effiPrimary)
                }
            }
        }
    }
}
