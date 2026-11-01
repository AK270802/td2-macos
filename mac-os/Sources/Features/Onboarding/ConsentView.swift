import SwiftUI
import EffiLensKit

/// Onboarding step 2 (prototype `obStep===2`): "Your privacy, clearly." —
/// Records / Never records cards, the tenant's published policy, consent
/// checkbox, Back / I Agree. Server-tracked via /consent/status → /consent/accept.
struct ConsentView: View {
    @Environment(AppModel.self) private var model
    let consent: ConsentStatusResponse
    var onBack: (() -> Void)?

    @State private var agreed = false
    @State private var isSubmitting = false
    @State private var error: AppError?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingHeading(prefix: "Your privacy, ", emphasis: "clearly", subtitle: "Here’s exactly what EffiLens records on this Mac.")

            HStack(alignment: .top, spacing: 12) {
                Card("Records", symbol: "checkmark") {
                    bulletList(["Work session start / stop", "Active app & window title", "Activity level (counts only)", "Blurred window screenshots"], mark: "✓")
                }
                Card("Never records", symbol: "xmark") {
                    bulletList(["What you type or passwords", "Full web addresses", "Microphone or camera", "Anything when tracking is off"], mark: "✕")
                }
            }
            .padding(.top, 14)

            if let content = consent.policyContent, !content.isEmpty {
                ScrollView {
                    Text(content).font(Typo.caption).foregroundStyle(Palette.textSecondary).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }
                .frame(height: 54)
                .background(Palette.inset, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).strokeBorder(Palette.hairline))
                .padding(.top, 10)
            }

            Toggle(isOn: $agreed) {
                Text(consent.policyVersion == nil
                     ? "No monitoring policy published yet — tracking stays off until there is one."
                     : "I understand and consent to EffiLens recording work activity as described.")
                    .font(Typo.body).foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(.checkbox)
            .tint(Palette.accent)
            .disabled(consent.policyVersion == nil)
            .padding(.top, 16)

            if let error {
                Text(error.userMessage).font(.system(size: 12)).foregroundStyle(Palette.danger).padding(.top, 6)
            }

            Spacer(minLength: 0)
            OnboardingFooter(step: .privacy) {
                if let onBack {
                    Button("Back", action: onBack).buttonStyle(.effi)
                } else {
                    Button("Sign Out") { Task { await model.signOut() } }.buttonStyle(.effi)
                }
                Button {
                    Task { await accept() }
                } label: {
                    HStack(spacing: 6) {
                        if isSubmitting { ProgressView().controlSize(.small) }
                        Text("I Agree")
                    }
                }
                .buttonStyle(.effiPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(!agreed || isSubmitting || consent.policyVersion == nil)
            }
        }
    }

    private func bulletList(_ items: [String], mark: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(mark)
                    Text(item).lineLimit(2)
                }
                .font(Typo.body)
                .foregroundStyle(Palette.textSecondary)
                .padding(.vertical, 4)
            }
        }
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
