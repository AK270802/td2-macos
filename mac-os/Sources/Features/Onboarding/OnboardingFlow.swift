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
        }
        .frame(width: Metrics.onboardingWindow.width, height: Metrics.onboardingWindow.height)
        .background(GlassBackdrop())
        .clipped()
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
            LinearGradient(colors: [Color(hex: 0x122244), Color(hex: 0x080E1C)], startPoint: UnitPoint(x: 0.2, y: 0), endPoint: UnitPoint(x: 0.8, y: 1))
            // Concentric ring (520 pt, left −120, top 120) with two faint halos.
            Circle()
                .strokeBorder(Palette.accentHighlight.opacity(0.25), lineWidth: 1)
                .background(Circle().stroke(Palette.accentHighlight.opacity(0.03), lineWidth: 80))
                .background(Circle().stroke(Palette.accentHighlight.opacity(0.025), lineWidth: 180))
                .frame(width: 520, height: 520)
                .position(x: -120 + 260, y: 120 + 260)
            // Official logo where the prototype draws its orb (220 pt at 60, 150).
            BrandLogoTile(size: 170, glow: true)
                .position(x: 60 + 110, y: 150 + 110)
                .offset(y: floating ? -10 : 0)
                .animation(reduceMotion ? nil : .easeInOut(duration: 3).repeatForever(autoreverses: true), value: floating)
            VStack(alignment: .leading, spacing: 8) {
                (Text("See your\n").font(Typo.serif(36))
                 + Text("work").font(Typo.serifItalic(36))
                 + Text(" clearly.").font(Typo.serif(36)))
                    .foregroundStyle(.white)
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
            HeroTitle(prefix: prefix, emphasis: emphasis, suffix: suffix, size: 34)
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
    var firstFailure: String? {
        for item in items { if case .failed(let message) = item.state { return message } }
        return nil
    }
    var anyFailed: Bool { items.contains { if case .failed = $0.state { return true } else { return false } } }

    init(deviceName: String) {
        items = [
            Item(id: 0, title: "Verifying organisation"),
            Item(id: 1, title: "Registering this Mac"),
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
            HeroTitle(prefix: "Hi \(firstName) — let’s set up\nthis ", emphasis: "Mac", suffix: ".", size: 34)
                .fixedSize(horizontal: false, vertical: true)
            Text("We’re registering this Mac with \(model.user?.organizationName ?? "your organisation").")
                .font(Typo.body).foregroundStyle(Palette.textSecondary).padding(.top, 8)

            Card(padding: Space.l) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(checklist.items) { item in
                        HStack(spacing: 10) {
                            statusIcon(item.state).frame(width: 18, height: 18)
                            Text(item.title).font(Typo.body).lineLimit(1)
                                .foregroundStyle(item.state == .done ? Palette.textPrimary : Palette.textSecondary)
                        }
                        .padding(.vertical, 7)
                    }
                }
            }
            .padding(.top, 22)

            if let failure = checklist.firstFailure {
                Text(failure).font(Typo.caption).foregroundStyle(Palette.danger).lineLimit(2).padding(.top, 10)
            }
            Text("macOS \(DeviceInfo.osVersion) · \(DeviceInfo.chip)")
                .font(Typo.caption).foregroundStyle(Palette.textTertiary).lineLimit(1).padding(.top, 8)

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
