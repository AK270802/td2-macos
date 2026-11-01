import SwiftUI
import EffiLensKit

@main
struct EffiLensApp: App {
    @State private var model: AppModel

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
                .task { await model.start() }
        }
        .defaultSize(width: 1200, height: 780)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands { EffiLensCommands(model: model) }

        MenuBarExtra {
            MenuBarPopover()
                .environment(model)
        } label: {
            MenuBarLabel()
                .environment(model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsPlaceholderView()
                .environment(model)
        }
    }
}

enum SceneID {
    static let main = "main"
}

/// App menu commands (prototype: File / View / Tracking menus).
struct EffiLensCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {}
                .disabled(true) // Milestone 7 (update architecture: BUILD_AND_RELEASE.md)
        }
        CommandMenu("Tracking") {
            Button("Start / Pause") {
                Task { try? await model.environment?.agent?.togglePlayPause() }
            }
            .keyboardShortcut(.space, modifiers: [.control, .option])
            .disabled(!model.isAgentConnected)

            Button("Stop") {
                Task { try? await model.environment?.agent?.stopTracking() }
            }
            .keyboardShortcut("s", modifiers: [.control, .option])
            .disabled(!model.isAgentConnected)
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
