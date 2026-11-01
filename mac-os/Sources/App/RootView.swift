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
        .background(GlassBackdrop())
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
/// Sizes are the full window frame — the transparent title bar overlays the
/// content exactly like the prototype's `.titlebar`.
struct WindowConfigurator: NSViewRepresentable {
    let onboarding: Bool
    /// Deterministic size (visual review); always applied.
    var fixedSize: CGSize?

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let onboarding = self.onboarding
        let fixedSize = self.fixedSize
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = onboarding
            let target = fixedSize ?? (onboarding ? Metrics.onboardingWindow : Metrics.mainWindow)
            let minimum = onboarding ? Metrics.onboardingWindow : Metrics.mainWindowMin
            if onboarding || fixedSize != nil {
                window.styleMask.remove(.resizable)
            } else {
                window.styleMask.insert(.resizable)
            }
            window.minSize = fixedSize ?? minimum
            window.maxSize = (onboarding || fixedSize != nil) ? target : CGSize(width: 10_000, height: 10_000)
            let current = window.frame.size
            let leavingOnboarding = context.coordinator.lastOnboarding == true && !onboarding
            let needsResize = fixedSize != nil || onboarding
                ? current != target
                : (current.width < minimum.width || current.height < minimum.height || leavingOnboarding)
            if needsResize {
                window.setFrame(NSRect(origin: window.frame.origin, size: target), display: true)
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
