import SwiftUI
import Observation
import EffiLensKit

@MainActor
@Observable
final class SignInViewModel {
    var email = ""
    var password = ""
    private(set) var isSubmitting = false
    private(set) var error: AppError?

    var canSubmit: Bool {
        !isSubmitting && email.contains("@") && !password.isEmpty
    }

    private(set) var resetMessage: String?

    func requestReset(model: AppModel) async {
        guard email.contains("@"), let environment = model.environment else {
            error = .validation("Enter your work email first.")
            return
        }
        do {
            let response = try await environment.profile.forgotPassword(email: email.trimmingCharacters(in: .whitespaces))
            resetMessage = response.message
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown("forgot-password")
        }
    }

    func prefill(from session: SessionManager) async {
        if email.isEmpty, let last = await session.lastEmail { email = last }
    }

    func submit(model: AppModel) async {
        guard canSubmit, let environment = model.environment else { return }
        isSubmitting = true
        error = nil
        defer { isSubmitting = false }
        do {
            try await environment.session.signIn(email: email, password: password)
            password = ""
            // The agent token is handed to the native daemon by AppModel once
            // it is reachable (also after launchd restarts it).
            await model.completeSignIn()
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown("sign-in")
        }
    }
}

/// Onboarding step 0 (prototype `obStep===0`): app icon + name, 34 pt
/// "Welcome back." heading, labelled 30 pt fields, large primary Sign In,
/// SSO button, error line, dots and the API host with connection state.
struct SignInView: View {
    @Environment(AppModel.self) private var model
    @State private var viewModel = SignInViewModel()
    @FocusState private var focused: Field?
    @AppStorage(Prefs.rememberMac) private var rememberMac = true
    @State private var reachable: Bool?

    private enum Field { case email, password }

    var body: some View {
        OnboardingWindow {
            HStack(spacing: 10) {
                AppIconTile(size: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text("EffiLens").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.textPrimary)
                    Text("Work, time & leave").font(Typo.caption).foregroundStyle(Palette.textTertiary)
                }
            }

            OnboardingHeading(prefix: "Welcome ", emphasis: "back", subtitle: "Sign in with your organisation account.")
                .padding(.top, 28)

            FieldLabel("Work email")
            TextField("name@company.com", text: $viewModel.email)
                .textFieldStyle(.plain)
                .textContentType(.username)
                .focused($focused, equals: .email)
                .onSubmit { focused = .password }
                .modifier(EffiFieldBackground(focused: focused == .email))
            FieldLabel("Password")
            SecureField("Password", text: $viewModel.password)
                .textFieldStyle(.plain)
                .textContentType(.password)
                .focused($focused, equals: .password)
                .onSubmit { Task { await viewModel.submit(model: model) } }
                .modifier(EffiFieldBackground(focused: focused == .password))

            HStack {
                Toggle("Remember this Mac", isOn: $rememberMac)
                    .toggleStyle(.checkbox)
                    .font(Typo.body)
                    .foregroundStyle(Palette.textSecondary)
                    .help("When off, you are signed out the next time EffiLens starts.")
                Spacer()
                Button("Forgot password?") { Task { await viewModel.requestReset(model: model) } }
                    .buttonStyle(.plain)
                    .font(Typo.body)
                    .foregroundStyle(Palette.accentText)
            }
            .padding(.top, 10)

            Button {
                Task { await viewModel.submit(model: model) }
            } label: {
                HStack(spacing: 6) {
                    if viewModel.isSubmitting { ProgressView().controlSize(.small).tint(Palette.onAccent) }
                    Text(viewModel.isSubmitting ? "Signing in…" : "Sign In")
                }
            }
            .buttonStyle(.effiButton(.primary, .large, fullWidth: true))
            .keyboardShortcut(.defaultAction)
            .disabled(!viewModel.canSubmit)
            .padding(.top, 20)

            // Desktop SSO needs a backend code-exchange endpoint (API_INTEGRATION.md gap B2).
            Button {} label: { Label("Sign in with SSO", systemImage: "key") }
                .buttonStyle(.effiButton(.normal, .large, fullWidth: true))
                .disabled(true)
                .help("Single sign-on for the desktop app is not available yet. Use your EffiLens password.")
                .padding(.top, 8)

            Group {
                if let error = viewModel.error {
                    Text(error.userMessage).foregroundStyle(Palette.danger)
                } else if let reset = viewModel.resetMessage {
                    Text(reset).foregroundStyle(Palette.success)
                }
            }
            .font(.system(size: 12))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)

            Spacer(minLength: 0)
            OnboardingFooter(step: .signIn) {
                if let host = model.environment?.configuration.apiOrigin.host() {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(reachable == true ? Palette.okFill : (reachable == false ? Palette.redFill : Palette.textTertiary))
                            .frame(width: 7, height: 7)
                            .shadow(color: reachable == true ? Palette.okFill : .clear, radius: 3)
                        Text("\(host) · \(reachable == true ? "Connected" : (reachable == false ? "Unreachable" : "Checking…"))")
                            .font(Typo.caption).foregroundStyle(Palette.textSecondary)
                    }
                    .help("Server this app signs in to")
                }
            }
        }
        .disabled(viewModel.isSubmitting)
        .task {
            if let session = model.environment?.session { await viewModel.prefill(from: session) }
            focused = viewModel.email.isEmpty ? .email : .password
        }
        .task {
            // Real reachability: unauthenticated GET /agent/version.
            guard let environment = model.environment else { return }
            reachable = (try? await environment.agentAPI.latestVersion()) != nil
        }
    }
}
