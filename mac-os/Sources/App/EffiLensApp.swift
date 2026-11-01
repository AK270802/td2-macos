import AppKit
import SwiftUI
import EffiLensKit

@main
struct EffiLensApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel
    @AppStorage(Prefs.appearance) private var appearance = "system"
    @AppStorage(Prefs.menuBarTimer) private var menuBarTimer = true

    init() {
        do {
            _model = State(initialValue: AppModel(environment: try AppEnvironment.live()))
        } catch let error as AppError {
            _model = State(initialValue: AppModel(environment: nil, configurationError: error.userMessage))
        } catch {
            _model = State(initialValue: AppModel(environment: nil, configurationError: "EffiLens could not start."))
        }
    }

    var body: some Scene {
        Window("EffiLens", id: SceneID.main) {
            mainContent
        }
        .defaultSize(width: Metrics.onboardingWindow.width, height: Metrics.onboardingWindow.height)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands { EffiLensCommands(model: model) }

        Window("Mini Timer", id: SceneID.miniTimer) {
            MiniTimerView()
                .environment(model)
                .effiLensAppearance(appearance)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)

        MenuBarExtra {
            MenuBarPopover()
                .environment(model)
                .effiLensAppearance(appearance)
        } label: {
            MenuBarLabel(showsTimer: menuBarTimer)
                .environment(model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsRootView()
                .environment(model)
                .effiLensAppearance(appearance)
        }
    }
}

extension EffiLensApp {
    @ViewBuilder
    private var mainContent: some View {
        #if DEBUG
        if let screen = ReviewMode.screen {
            ReviewHostView(screen: screen).environment(model)
        } else {
            liveRoot
        }
        #else
        liveRoot
        #endif
    }

    private var liveRoot: some View {
        RootView()
            .environment(model)
            .effiLensAppearance(appearance)
            .task {
                appDelegate.model = model
                await model.start()
            }
    }
}

enum SceneID {
    static let main = "main"
    static let miniTimer = "mini-timer"
}

/// App menu commands (prototype: File / View / Tracking menus).
struct EffiLensCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                UpdateDialog.present(version: model.environment?.configuration.appVersion ?? "—")
            }
        }
        CommandMenu("Tracking") {
            Button("Start / Pause") {
                Task { await model.runAgent { try await $0.togglePlayPause() } }
            }
            .keyboardShortcut(.space, modifiers: [.control, .option])
            .disabled(!model.isAgentConnected)

            Button("Stop") {
                Task { await model.runAgent { try await $0.stopTracking() } }
            }
            .keyboardShortcut("s", modifiers: [.control, .option])
            .disabled(!model.isAgentConnected)

            Divider()
            Button("Sync Now") {
                Task { await model.runAgent { try await $0.syncNow() } }
            }
            .disabled(!model.isAgentConnected)
            Button("Show Mini Timer") { openWindow(id: SceneID.miniTimer) }
                .keyboardShortcut("m", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .newItem) {}
    }
}

extension AppModel {
    var isAgentConnected: Bool {
        if case .connected = agentLink { return true }
        return false
    }

    var timerState: AgentTimerState? {
        if case .connected(let state) = agentLink { return state }
        return nil
    }
}
