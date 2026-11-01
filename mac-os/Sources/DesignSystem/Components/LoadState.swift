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
/// emptiness predicate that switches to the prototype's `.empty` state.
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
            HStack(spacing: Space.s) {
                ProgressView().controlSize(.small).tint(Palette.accent)
                Text("Loading…").font(Typo.caption).foregroundStyle(Palette.textTertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .accessibilityElement(children: .combine)
        case .failed(let error):
            ErrorStateView(error: error, retry: retry)
        case .loaded(let value):
            if isEmpty(value) {
                EmptyStateView(title: emptyTitle, message: emptyMessage, symbol: emptySymbol)
            } else {
                content(value)
            }
        }
    }
}

/// `.empty` — centred tertiary text, generous padding.
struct EmptyStateView: View {
    let title: String
    var message: String = ""
    var symbol: String = "tray"

    var body: some View {
        VStack(spacing: Space.s) {
            Image(systemName: symbol).font(.system(size: 22, weight: .light)).foregroundStyle(Palette.textTertiary)
            Text(title).font(Typo.bodyEmphasis).foregroundStyle(Palette.textSecondary)
            if !message.isEmpty {
                Text(message).font(Typo.caption).foregroundStyle(Palette.textTertiary).multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 40)
        .padding(.horizontal, Space.xl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
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
        VStack(spacing: Space.s) {
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(Palette.danger)
            Text(error == .offline ? "You're offline" : "Couldn't load").font(Typo.bodyEmphasis).foregroundStyle(Palette.textPrimary)
            Text(error.userMessage).font(Typo.caption).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center)
            if let retry {
                Button("Try Again", action: retry).buttonStyle(.effi).keyboardShortcut("r", modifiers: .command).padding(.top, 4)
            }
        }
        .padding(.vertical, 32)
        .padding(.horizontal, Space.xl)
        .frame(maxWidth: .infinity)
    }
}
