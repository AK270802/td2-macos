import SwiftUI
import EffiLensKit

/// Uniform async state for every screen: never show fake data while loading.
enum Loadable<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(AppError)

    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

extension Loadable: Equatable where Value: Equatable {}

/// Renders loading / error / content for a `Loadable`, with an optional
/// emptiness predicate that switches to an empty state.
struct LoadStateView<Value, Content: View>: View {
    let state: Loadable<Value>
    var emptyTitle: String = "Nothing here yet"
    var emptyMessage: String = ""
    var emptySymbol: String = "tray"
    var isEmpty: (Value) -> Bool = { _ in false }
    var retry: (() -> Void)?
    @ViewBuilder var content: (Value) -> Content

    var body: some View {
        switch state {
        case .idle, .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 120)
                .accessibilityLabel("Loading")
        case .failed(let error):
            ErrorStateView(error: error, retry: retry)
        case .loaded(let value):
            if isEmpty(value) {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: emptySymbol)
                } description: {
                    if !emptyMessage.isEmpty { Text(emptyMessage) }
                }
                .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                content(value)
            }
        }
    }
}

struct ErrorStateView: View {
    let error: AppError
    var retry: (() -> Void)?

    private var symbol: String {
        switch error {
        case .offline: return "wifi.slash"
        case .forbidden: return "lock"
        case .agentUnavailable: return "bolt.horizontal.circle"
        default: return "exclamationmark.triangle"
        }
    }

    var body: some View {
        ContentUnavailableView {
            Label(error == .offline ? "Offline" : "Couldn't load", systemImage: symbol)
        } description: {
            Text(error.userMessage)
        } actions: {
            if let retry { Button("Try Again", action: retry).keyboardShortcut("r", modifiers: .command) }
        }
        .frame(maxWidth: .infinity, minHeight: 140)
    }
}
