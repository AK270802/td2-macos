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

/// Sign-in step of onboarding. Layout follows the prototype's onboarding
/// window (brand panel left, form right); identity uses official brand assets.
struct SignInView: View {
    @Environment(AppModel.self) private var model
    @State private var viewModel = SignInViewModel()
    @FocusState private var focused: Field?

    private enum Field { case email, password }

    var body: some View {
        HStack(spacing: 0) {
            brandPanel
                .frame(width: 340)
            form
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: 820, maxHeight: 560)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous).strokeBorder(Palette.hairline))
        .shadow(color: .black.opacity(0.08), radius: 24, y: 8)
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if let session = model.environment?.session { await viewModel.prefill(from: session) }
            focused = viewModel.email.isEmpty ? .email : .password
        }
    }

    private var brandPanel: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Image("BrandWordmark")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: 96)
                .accessibilityLabel("EffiLens")
            Spacer()
            Text("See your work clearly.")
                .font(Typo.title)
                .foregroundStyle(Palette.textPrimary)
            Text("Track time on your tasks, manage leave, and stay in sync with your team.")
                .font(Typo.body)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.xxl)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.inset)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Sign in").font(Typo.display).foregroundStyle(Palette.textPrimary)
                Text("Use your work account.").font(Typo.body).foregroundStyle(Palette.textSecondary)
            }

            VStack(alignment: .leading, spacing: Space.m) {
                TextField("Work email", text: $viewModel.email)
                    .textContentType(.username)
                    .focused($focused, equals: .email)
                    .onSubmit { focused = .password }
                SecureField("Password", text: $viewModel.password)
                    .textContentType(.password)
                    .focused($focused, equals: .password)
                    .onSubmit { Task { await viewModel.submit(model: model) } }
            }
            .textFieldStyle(.roundedBorder)
            .controlSize(.large)
            .disabled(viewModel.isSubmitting)

            if let error = viewModel.error {
                Label(error.userMessage, systemImage: "exclamationmark.circle")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isStaticText)
            }

            Button {
                Task { await viewModel.submit(model: model) }
            } label: {
                HStack {
                    if viewModel.isSubmitting { ProgressView().controlSize(.small) }
                    Text(viewModel.isSubmitting ? "Signing in…" : "Sign In")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!viewModel.canSubmit)

            // SSO for desktop clients requires a backend code-exchange endpoint
            // that does not exist yet (API_INTEGRATION.md gap B2). Shown disabled
            // with an explanation rather than hidden, to match the prototype.
            Button("Sign in with SSO") {}
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(true)
                .help("Single sign-on for the desktop app is not yet available. Use your EffiLens password.")

            Spacer()

            if let host = model.environment?.configuration.apiOrigin.host() {
                Label(host, systemImage: "server.rack")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(Space.xxl)
    }
}
