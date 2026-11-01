import AppKit
import SwiftUI
import UserNotifications
import EffiLensKit

// Prototype `#onboard`: one 820 × 560 window — 340 pt art panel + main panel
// (padding 54/44/28), four steps with dots: 0 Sign in · 1 Set up this Mac ·
// 2 Privacy consent · 3 Permissions. Every step uses real services.

enum OnboardingStep: Int, CaseIterable {
    case signIn, setup, privacy, permissions
}

/// The two-panel onboarding window body.
struct OnboardingWindow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) {
            OnboardingArtPanel()
                .frame(width: Metrics.onboardingArtWidth)
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(EdgeInsets(top: 54, leading: 44, bottom: 28, trailing: 44))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Palette.surfaceRaised)
        }
        .frame(width: Metrics.onboardingWindow.width, height: Metrics.onboardingWindow.height)
        .ignoresSafeArea()
    }
}

/// `.ob-art` — navy gradient, concentric amber ring, glowing amber orb,
/// caption bottom-left. Brand colours replace the prototype golds.
struct OnboardingArtPanel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floating = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color(hex: 0x0A2A55), Color(hex: 0x020E22)], startPoint: .topLeading, endPoint: .bottomTrailing)
            // Concentric ring (520 pt, left −120, top 120) with two faint halos.
            Circle()
                .strokeBorder(Brand.amber.opacity(0.25), lineWidth: 1)
                .background(Circle().stroke(Brand.amber.opacity(0.03), lineWidth: 80))
                .frame(width: 520, height: 520)
                .position(x: -120 + 260, y: 120 + 260)
            // Orb (220 pt at 60, 150).
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xFFD36B), Brand.amber, Color(hex: 0x5A3A0E)],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 4, endRadius: 150))
                .frame(width: 220, height: 220)
                .shadow(color: Brand.amber.opacity(0.45), radius: 60)
                .position(x: 60 + 110, y: 150 + 110)
                .offset(y: floating ? -14 : 0)
                .animation(reduceMotion ? nil : .easeInOut(duration: 3).repeatForever(autoreverses: true), value: floating)
            VStack(alignment: .leading, spacing: 8) {
                (Text("See your\n") + Text("work").foregroundColor(Brand.amber) + Text(" clearly."))
                    .font(.system(size: 36, weight: .regular))
                    .foregroundStyle(.white)
                    .lineSpacing(-2)
                Text("Time, focus and leave — beautifully in one place.")
                    .font(Typo.body)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(30)
        }
        .clipped()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("See your work clearly. Time, focus and leave in one place.")
        .onAppear { floating = true }
    }
}

/// `.ob-dots` — 6 pt dots, the active one a 20 pt accent capsule.
struct OnboardingDots: View {
    let current: OnboardingStep

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                Capsule()
                    .fill(step == current ? Palette.accent : Palette.divider)
                    .frame(width: step == current ? 20 : 6, height: 6)
            }
        }
        .animation(Motion.quick, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current.rawValue + 1) of \(OnboardingStep.allCases.count)")
    }
}

/// Footer row: dots on the left, actions on the right (prototype).
struct OnboardingFooter<Actions: View>: View {
    let step: OnboardingStep
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: Space.s) {
            OnboardingDots(current: step)
            Spacer()
            actions
        }
        .padding(.top, 14)
    }
}

/// Onboarding H1 (34 pt) with accent emphasis + muted subtitle.
struct OnboardingHeading: View {
    let prefix: String
    let emphasis: String
    var suffix: String = "."
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HeroTitle(prefix: prefix, emphasis: emphasis, suffix: suffix, font: Typo.display)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(Typo.body).foregroundStyle(Palette.textSecondary)
        }
    }
}

// MARK: - Post-sign-in flow (steps 1–3)

/// Shown after sign-in until setup completes, and whenever consent is
/// required again (new policy version).
struct PostSignInOnboarding: View {
    @Environment(AppModel.self) private var model
    @State var step: OnboardingStep
    var onFinish: () -> Void

    var body: some View {
        OnboardingWindow {
            switch step {
            case .signIn, .setup:
                SetupStepView { step = model.phase == .ready ? .permissions : .privacy }
            case .privacy:
                if case .consentRequired(let consent) = model.phase {
                    ConsentView(consent: consent, onBack: { step = .setup })
                } else {
                    // Already accepted on the server.
                    VStack(alignment: .leading, spacing: 0) {
                        OnboardingHeading(prefix: "Your privacy, ", emphasis: "clearly", subtitle: "You have already accepted your organisation's monitoring policy.")
                        Spacer()
                        OnboardingFooter(step: .privacy) {
                            Button("Continue") { step = .permissions }.buttonStyle(.effiPrimary)
                        }
                    }
                }
            case .permissions:
                PermissionsStepView(onBack: { step = .privacy }, onFinish: onFinish)
            }
        }
        .onChange(of: model.phase) { _, phase in
            if phase == .ready, step == .privacy { step = .permissions }
        }
    }
}

// MARK: Step 1 — set up this Mac (real checks)

@MainActor
@Observable
final class SetupChecklist {
    enum State: Equatable { case pending, running, done, failed(String) }

    struct Item: Identifiable {
        let id: Int
        let title: String
        var state: State = .pending
    }

    var items: [Item]
    var allDone: Bool { items.allSatisfy { $0.state == .done } }
    var anyFailed: Bool { items.contains { if case .failed = $0.state { return true } else { return false } } }

    init(deviceName: String) {
        items = [
            Item(id: 0, title: "Verifying organisation"),
            Item(id: 1, title: "Registering device “\(deviceName)”"),
            Item(id: 2, title: "Downloading tracking policy"),
            Item(id: 3, title: "Syncing projects & tasks"),
            Item(id: 4, title: "Fetching leave balances"),
        ]
    }

    func run(model: AppModel) async {
        guard let environment = model.environment else { return }
        for index in items.indices { items[index].state = .pending }
        let steps: [() async throws -> Void] = [
            { if model.user == nil { throw AppError.unauthenticated } },
            { if await environment.session.agentTokenForDaemon() == nil { throw AppError.unauthenticated } },
            { _ = try await environment.agentAPI.config() },
            { _ = try await environment.work.assignedProjects() },
            { _ = try await environment.leave.balance() },
        ]
        for (index, step) in steps.enumerated() {
            items[index].state = .running
            do {
                try await step()
                items[index].state = .done
            } catch {
                items[index].state = .failed(DashboardViewModel.map(error).userMessage)
            }
        }
    }
}

struct SetupStepView: View {
    @Environment(AppModel.self) private var model
    @State private var checklist = SetupChecklist(deviceName: DeviceInfo.name)
    var onContinue: () -> Void

    private var firstName: String {
        model.user?.displayName.split(separator: " ").first.map(String.init) ?? "there"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeroTitle(prefix: "Hi \(firstName) — let’s set up\nthis ", emphasis: "Mac", suffix: ".", font: Typo.display)
                .fixedSize(horizontal: false, vertical: true)
            Text("We’re registering this Mac with \(model.user?.organizationName ?? "your organisation").")
                .font(Typo.body).foregroundStyle(Palette.textSecondary).padding(.top, 8)

            Card(padding: Space.l) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(checklist.items) { item in
                        HStack(spacing: 10) {
                            statusIcon(item.state).frame(width: 18, height: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title).font(Typo.body)
                                    .foregroundStyle(item.state == .done ? Palette.textPrimary : Palette.textSecondary)
                                if case .failed(let message) = item.state {
                                    Text(message).font(Typo.small).foregroundStyle(Palette.danger)
                                }
                            }
                        }
                        .padding(.vertical, 7)
                    }
                }
            }
            .padding(.top, 22)

            Text("Device: \(DeviceInfo.name) · macOS \(DeviceInfo.osVersion) · \(DeviceInfo.chip)")
                .font(Typo.caption).foregroundStyle(Palette.textTertiary).padding(.top, 12)

            Spacer(minLength: 0)
            OnboardingFooter(step: .setup) {
                if checklist.anyFailed {
                    Button("Retry") { Task { await checklist.run(model: model) } }.buttonStyle(.effi)
                }
                Button("Continue", action: onContinue)
                    .buttonStyle(.effiPrimary)
                    .disabled(!checklist.allDone && !checklist.anyFailed)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .task { await checklist.run(model: model) }
    }

    @ViewBuilder
    private func statusIcon(_ state: SetupChecklist.State) -> some View {
        switch state {
        case .pending: Circle().strokeBorder(Palette.divider, lineWidth: 1.5).frame(width: 14, height: 14)
        case .running: ProgressView().controlSize(.small).tint(Palette.accent)
        case .done: Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.success)
        case .failed: Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.danger)
        }
    }
}

/// Real device facts for the setup step (no identifiers are sent anywhere).
enum DeviceInfo {
    static var name: String { Host.current().localizedName ?? "This Mac" }
    static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion)"
    }
    static var chip: String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }
}

// MARK: Step 3 — permissions

struct PermissionsStepView: View {
    var onBack: () -> Void
    var onFinish: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingHeading(prefix: "A few ", emphasis: "permissions", subtitle: "macOS will ask you to confirm each one.")
            ScrollView {
                PermissionsList().padding(.top, 16)
            }
            .scrollIndicators(.never)
            OnboardingFooter(step: .permissions) {
                Button("Back", action: onBack).buttonStyle(.effi)
                Button(model.permissions.map { $0.accessibility && $0.screenRecording && $0.inputMonitoring } == true ? "Get Started" : "Continue Anyway",
                       action: onFinish)
                    .buttonStyle(.effiPrimary)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
