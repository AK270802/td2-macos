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
            RootView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 620)
                .effiLensAppearance(appearance)
                .task {
                    appDelegate.model = model
                    await model.start()
                }
        }
        .defaultSize(width: 1200, height: 780)
        .windowToolbarStyle(.unified(showsTitle: false))
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
