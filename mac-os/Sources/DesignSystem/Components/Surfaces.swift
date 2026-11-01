import SwiftUI

/// Standard content card (portal `SectionCard`): white surface, hairline
/// border, very soft shadow. No accent borders, no gradients.
struct Card<Content: View>: View {
    var title: String?
    var subtitle: String?
    var trailing: AnyView?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, subtitle: String? = nil, trailing: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if title != nil || trailing != nil {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        if let title { Text(title).font(Typo.heading).foregroundStyle(Palette.textPrimary) }
                        if let subtitle { Text(subtitle).font(Typo.caption).foregroundStyle(Palette.textSecondary) }
                    }
                    Spacer(minLength: Space.s)
                    trailing
                }
            }
            content
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Palette.hairline))
        .shadow(color: Color.black.opacity(0.04), radius: 10, y: 3)
    }
}

/// KPI tile (portal `StatTile`): overline label, monospaced value, optional footnote.
struct StatTile: View {
    let label: String
    let value: String
    var footnote: String?
    var footnoteTone: Color = Palette.textSecondary
    var progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(label.uppercased())
                .font(Typo.overline)
                .tracking(0.6)
                .foregroundStyle(Palette.textTertiary)
            Text(value)
                .font(Typo.kpi)
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let progress {
                ProgressView(value: min(max(progress, 0), 1))
                    .progressViewStyle(.linear)
                    .tint(Palette.accent)
            }
            if let footnote {
                Text(footnote).font(Typo.caption).foregroundStyle(footnoteTone).lineLimit(1)
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Palette.hairline))
        .accessibilityElement(children: .combine)
    }
}

/// Status pill (portal `GlassBadge` variants).
struct StatusPill: View {
    enum Tone { case neutral, success, warning, danger, info, accent }
    let text: String
    var tone: Tone = .neutral

    private var color: Color {
        switch tone {
        case .neutral: return Palette.textSecondary
        case .success: return Palette.success
        case .warning: return Palette.warning
        case .danger: return Palette.danger
        case .info: return Palette.info
        case .accent: return Palette.accent
        }
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, Space.s)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
            .accessibilityLabel(text)
    }
}

/// Circular progress ring used for the active session and leave balances.
struct ProgressRing<Center: View>: View {
    var progress: Double
    var lineWidth: CGFloat = 8
    var tint: Color = Palette.accent
    @ViewBuilder var center: Center
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(Palette.hairline, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : Motion.ring, value: progress)
            center
        }
    }
}

/// Initials avatar on the brand navy.
struct InitialsAvatar: View {
    let initials: String
    var size: CGFloat = 28

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Brand.navy, in: Circle())
            .accessibilityHidden(true)
    }
}

/// The official EffiLens mark from the asset catalogue.
struct BrandMark: View {
    var size: CGFloat = 28
    var body: some View {
        Image("BrandMark")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel("EffiLens")
    }
}
