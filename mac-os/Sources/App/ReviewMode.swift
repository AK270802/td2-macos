#if DEBUG
import AppKit
import SwiftUI
import EffiLensKit

/// Visual-review harness (DEBUG builds only — compiled out of Release).
///
/// `EffiLens -EffiLensReview <screen> -EffiLensReviewAppearance light|dark -EffiLensReviewOutput <file.png>`
///
/// Renders one screen in a deterministic window size, writes the window's own
/// contents to PNG via `NSView.cacheDisplay` (no Screen Recording permission
/// needed) and quits. The app is **not signed in** in review mode: screens show
/// their real loading / empty / error states — no fixture or fake data.
enum ReviewMode {
    static var screen: String? { UserDefaults.standard.string(forKey: "EffiLensReview") }
    static var appearance: String { UserDefaults.standard.string(forKey: "EffiLensReviewAppearance") ?? "light" }
    static var output: String? { UserDefaults.standard.string(forKey: "EffiLensReviewOutput") }
    static var isActive: Bool { screen != nil }

    static let onboardingScreens: Set<String> = ["signin", "onboarding-setup", "onboarding-privacy", "onboarding-permissions"]

    /// Captures the key window to `output` after `delay`, then terminates.
    @MainActor
    static func scheduleCapture(delay: Duration = .seconds(6)) {
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            defer { NSApp.terminate(nil) }
            guard let output,
                  let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && $0.frame.width > 200 }),
                  let view = window.contentView else { return }
            view.layoutSubtreeIfNeeded()
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { return }
            try? FileManager.default.createDirectory(at: URL(fileURLWithPath: output).deletingLastPathComponent(), withIntermediateDirectories: true)
            try? png.write(to: URL(fileURLWithPath: output))
        }
    }
}

/// Hosts the requested screen for review capture.
struct ReviewHostView: View {
    @Environment(AppModel.self) private var model
    let screen: String

    private var isOnboarding: Bool { ReviewMode.onboardingScreens.contains(screen) }

    var body: some View {
        content
            .background(GlassBackdrop())
            .background(WindowConfigurator(onboarding: isOnboarding, fixedSize: isOnboarding ? Metrics.onboardingWindow : Metrics.mainWindow))
            .preferredColorScheme(ReviewMode.appearance == "dark" ? .dark : .light)
            .onAppear { ReviewMode.scheduleCapture() }
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case "signin":
            SignInView()
        case "onboarding-setup":
            PostSignInOnboarding(step: .setup) {}
        case "onboarding-privacy":
            OnboardingWindow { ConsentView(consent: Self.unpublishedPolicy, onBack: {}) }
        case "onboarding-permissions":
            OnboardingWindow { PermissionsStepView(onBack: {}, onFinish: {}) }
        case "menubar":
            MenuBarPopover().background(Palette.surfaceRaised).frame(maxWidth: .infinity, maxHeight: .infinity)
        case "mini":
            MiniTimerView().frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            MainShellView(initialRoute: Route(rawValue: screen) ?? .dashboard)
        }
    }

    /// Real decoding of a "no published policy" response (the actual state
    /// the consent step shows when a tenant has no policy).
    private static let unpublishedPolicy: ConsentStatusResponse = {
        let json = Data(#"{"status":null,"policy_version":null,"policy_content":null}"#.utf8)
        return (try? JSONCoding.makeDecoder().decode(ConsentStatusResponse.self, from: json))!
    }()
}
#endif
