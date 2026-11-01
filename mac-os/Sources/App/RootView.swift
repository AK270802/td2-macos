import SwiftUI
import EffiLensKit

/// Routes between launch, onboarding/sign-in, consent and the main shell.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("effilens.onboarding.welcomeSeen") private var welcomeSeen = false
    @AppStorage("effilens.onboarding.setupDone") private var setupDone = false

    var body: some View {
        Group {
            switch model.phase {
            case .launching:
                LaunchView()
            case .signedOut:
                if welcomeSeen { SignInView() } else { WelcomeView { welcomeSeen = true } }
            case .consentRequired(let consent):
                ConsentView(consent: consent)
            case .passwordChangeRequired:
                PasswordChangeRequiredView()
            case .ready:
                if setupDone { MainShellView() } else { SetupFlowView { setupDone = true } }
            case .configurationError(let message):
                ContentUnavailableView("EffiLens can't start", systemImage: "exclamationmark.octagon", description: Text(message))
            }
        }
        .background(Palette.canvas)
        .animation(Motion.quick, value: model.phase)
    }
}

private struct LaunchView: View {
    var body: some View {
        VStack(spacing: Space.l) {
            BrandMark(size: 72)
            ProgressView().controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Starting EffiLens")
    }
}

/// The backend blocks portal APIs until the password is changed (403 +
/// X-Password-Change-Required). The change-password form ships in Milestone 2b;
/// until then, the user is directed to the portal rather than shown a dead end.
private struct PasswordChangeRequiredView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("Password change required", systemImage: "key")
        } description: {
            Text(AppError.passwordChangeRequired.userMessage)
        } actions: {
            if let portal = model.environment?.configuration.portalOrigin {
                Link("Change Password in Portal", destination: portal.appending(path: "change-password"))
            }
            Button("Sign Out") { Task { await model.signOut() } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
