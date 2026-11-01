import SwiftUI
import EffiLensKit

/// Privacy consent gate (server-tracked via /consent/status → /consent/accept).
/// Content comes from the tenant's published policy, never hardcoded.
struct ConsentView: View {
    @Environment(AppModel.self) private var model
    let consent: ConsentStatusResponse

    @State private var agreed = false
    @State private var isSubmitting = false
    @State private var error: AppError?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(spacing: Space.m) {
                BrandMark(size: 36)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text("Monitoring policy").font(Typo.title)
                    if let version = consent.policyVersion {
                        Text("Version \(version)").font(Typo.caption).foregroundStyle(Palette.textSecondary)
                    }
                }
            }

            privacySummary

            ScrollView {
                Text(consent.policyContent ?? "Your organisation has not published a monitoring policy yet. Tracking stays disabled until one is available.")
                    .font(Typo.body)
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.l)
            }
            .background(Palette.inset, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))

            Toggle("I have read and accept this policy", isOn: $agreed)
                .toggleStyle(.checkbox)
                .disabled(consent.policyVersion == nil)

            if let error {
                Text(error.userMessage).font(Typo.caption).foregroundStyle(Palette.danger)
            }

            HStack {
                Button("Sign Out") { Task { await model.signOut() } }
                Spacer()
                Button {
                    Task { await accept() }
                } label: {
                    if isSubmitting { ProgressView().controlSize(.small) } else { Text("Accept & Continue") }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!agreed || isSubmitting || consent.policyVersion == nil)
            }
        }
        .padding(Space.xxl)
        .frame(maxWidth: 720, maxHeight: 640)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Plain-language summary of what is and isn't captured (CLAUDE.md privacy rules).
    private var privacySummary: some View {
        HStack(alignment: .top, spacing: Space.xl) {
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Recorded while tracking").font(Typo.overline).foregroundStyle(Palette.textTertiary)
                Label("Active app and window title", systemImage: "macwindow")
                Label("Website domain only (e.g. github.com)", systemImage: "globe")
                Label("Activity level as counts", systemImage: "waveform.path.ecg")
                Label("Blurred screenshots of the active window", systemImage: "camera.metering.center.weighted")
            }
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Never recorded").font(Typo.overline).foregroundStyle(Palette.textTertiary)
                Label("What you type", systemImage: "keyboard")
                Label("Full URLs or page content", systemImage: "link")
                Label("Microphone or camera", systemImage: "mic.slash")
                Label("Anything while tracking is off", systemImage: "pause.circle")
            }
        }
        .font(Typo.body)
        .foregroundStyle(Palette.textSecondary)
    }

    private func accept() async {
        guard let version = consent.policyVersion, let environment = model.environment else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await environment.consent.accept(policyVersion: version)
            await model.consentAccepted()
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown("consent")
        }
    }
}
