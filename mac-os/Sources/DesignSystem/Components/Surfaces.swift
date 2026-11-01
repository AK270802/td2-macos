import AppKit
import SwiftUI

// Surfaces and data-display components, specified by the prototype CSS
// (`.card`, `.kpi`, `.pill`, `.ring`, `.avatar`, `.listi`, `.ic`, `.tl`).

/// `.card` — radius 14, padding 16, 1 pt line border, soft shadow. The header
/// (`.card h4`) is 12 pt semibold secondary text with an optional symbol and a
/// trailing accessory (`.r`).
struct Card<Content: View>: View {
    var title: String?
    var symbol: String?
    var subtitle: String?
    var trailing: AnyView?
    var padding: CGFloat = Space.l
    var tint: Color?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, symbol: String? = nil, subtitle: String? = nil, trailing: AnyView? = nil,
         padding: CGFloat = Space.l, tint: Color? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.subtitle = subtitle
        self.trailing = trailing
        self.padding = padding
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if title != nil || trailing != nil {
                HStack(spacing: 6) {
                    if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)) }
                    if let title { Text(title).font(Typo.cardHeader) }
                    Spacer(minLength: Space.s)
                    trailing
                }
                .foregroundStyle(Palette.textSecondary)
                if let subtitle {
                    Text(subtitle).font(Typo.caption).foregroundStyle(Palette.textTertiary).padding(.top, -6)
                }
            }
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(CardBackground(tint: tint))
    }
}

/// Card fill + border + shadow, reusable for custom containers.
struct CardBackground: View {
    var tint: Color?
    var radius: CGFloat = Radius.card
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(tint.map { AnyShapeStyle($0.opacity(0.08)) } ?? AnyShapeStyle(Palette.surface))
            .overlay(
                // Prototype: gradient white 5.5 % → 2 % on dark; flat white 85 % on light.
                shape.fill(LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.035 : 0), .clear],
                                          startPoint: .top, endPoint: .bottom))
            )
            .overlay(shape.strokeBorder(Palette.hairline))
            .shadow(color: .black.opacity(scheme == .dark ? 0.18 : 0.05), radius: 12, y: 6)
    }
}

/// Card-header trailing link (prototype gold "See all" / "Details").
struct CardLink: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }
    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(Typo.cardHeader)
            .foregroundStyle(Palette.accentText)
    }
}

/// `.kpi` — SF Mono 26 semibold, optional 12 pt tertiary suffix (`<small>`).
struct KPIText: View {
    let value: String
    var suffix: String?

    var body: some View {
        (Text(value).font(Typo.kpi).foregroundStyle(Palette.textPrimary)
         + Text(suffix.map { " \($0)" } ?? "").font(Typo.kpiSuffix).foregroundStyle(Palette.textTertiary))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .contentTransition(.numericText())
    }
}

/// KPI card (`.card` + `h4` + `.kpi` + trend/footnote/progress).
struct StatTile: View {
    let label: String
    let value: String
    var symbol: String?
    var suffix: String?
    var footnote: String?
    var footnoteTone: Color = Palette.textTertiary
    var progress: Double?
    var progressTint: Color = Palette.blueFill

    var body: some View {
        Card(label, symbol: symbol) {
            VStack(alignment: .leading, spacing: 6) {
                KPIText(value: value, suffix: suffix)
                if let progress {
                    ProgressBar(value: progress, tint: progressTint).padding(.top, 4)
                }
                if let footnote {
                    Text(footnote).font(Typo.caption).foregroundStyle(footnoteTone).lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// `.prog` — 5 pt rounded bar.
struct ProgressBar: View {
    var value: Double
    var tint: Color = Palette.accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.hairline)
                Capsule().fill(tint).frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 5)
        .accessibilityValue("\(Int((min(max(value, 0), 1)) * 100)) percent")
    }
}

/// `.pill` variants.
struct Pill: View {
    enum Kind { case ok, wait, no, gray, blue, vio, accent }
    let text: String
    var kind: Kind = .gray
    var dot = false
    var symbol: String?

    private var color: Color {
        switch kind {
        case .ok: return Palette.success
        case .wait: return Palette.warning
        case .no: return Palette.danger
        case .gray: return Palette.textSecondary
        case .blue: return Palette.info
        case .vio: return Palette.violet
        case .accent: return Palette.accentText
        }
    }

    private var fill: Color {
        switch kind {
        case .gray: return Palette.textPrimary.opacity(0.08)
        case .accent: return Palette.accent.opacity(0.18)
        default: return color.opacity(0.15)
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            if dot { Circle().fill(color).frame(width: 6, height: 6) }
            if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .bold)) }
            Text(text)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(fill, in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// Backwards-compatible tone API used across screens → `Pill`.
struct StatusPill: View {
    enum Tone { case neutral, success, warning, danger, info, accent, violet }
    let text: String
    var tone: Tone = .neutral
    var dot = false

    var body: some View {
        Pill(text: text, kind: kind, dot: dot)
    }

    private var kind: Pill.Kind {
        switch tone {
        case .neutral: return .gray
        case .success: return .ok
        case .warning: return .wait
        case .danger: return .no
        case .info: return .blue
        case .accent: return .accent
        case .violet: return .vio
        }
    }
}

/// `.ring` — gradient stroke (brand highlight → accent) over an 8 % track.
struct ProgressRing<Center: View>: View {
    var progress: Double
    var lineWidth: CGFloat = 8
    var tint: Color?
    @ViewBuilder var center: Center
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(Palette.textPrimary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(LinearGradient(colors: [Palette.accentHighlight, Palette.accent], startPoint: .leading, endPoint: .trailing)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : Motion.ring, value: progress)
            center
        }
    }
}

/// `.avatar` — accent gradient circle with dark initials.
struct InitialsAvatar: View {
    let initials: String
    var size: CGFloat = 30
    var color: Color?

    var body: some View {
        Text(initials.uppercased())
            .font(.system(size: max(11, size * 0.36), weight: .bold))
            .foregroundStyle(Palette.onAccent)
            .frame(width: size, height: size)
            .background(
                color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(LinearGradient(colors: [Palette.accentHighlight, Palette.accent], startPoint: .topLeading, endPoint: .bottomTrailing)),
                in: Circle()
            )
            .accessibilityHidden(true)
    }
}

extension String {
    /// Up to two initials from a display name or email.
    var initials: String {
        let parts = split(whereSeparator: { $0 == " " || $0 == "." || $0 == "@" }).prefix(2)
        return parts.compactMap(\.first).map(String.init).joined().uppercased()
    }
}

/// Stable per-identifier colour for avatars / project dots (no meaning implied).
enum IdentityColor {
    static let palette: [Color] = [Palette.okFill, Palette.blueFill, Palette.violetFill, Color(hex: 0xF0C779), Palette.redFill, Color(hex: 0x5AC8FA)]
    static func color(for id: UUID) -> Color {
        palette[Int(id.uuid.0) % palette.count]
    }
}

/// `.ic` — 32 pt rounded icon tile tinted at 18–22 %.
struct IconTile: View {
    let symbol: String
    var tint: Color = Palette.accent
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// `.listi` — icon/leading, title + dim subtitle, trailing accessory; hairline separator.
struct ListItemRow<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    var bold = false
    var showsDivider = true
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.m) {
                leading
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(bold ? Typo.bodyEmphasis : Typo.body).foregroundStyle(Palette.textPrimary).lineLimit(1)
                    if let subtitle { Text(subtitle).font(Typo.small).foregroundStyle(Palette.textTertiary).lineLimit(2) }
                }
                Spacer(minLength: Space.s)
                trailing
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            if showsDivider { Divider().overlay(Palette.hairline) }
        }
        .contentShape(Rectangle())
    }
}

/// Date block used in "Upcoming" and holiday lists (month overline + mono day).
struct DateBlock: View {
    let date: Date

    var body: some View {
        VStack(spacing: 0) {
            Text(date.formatted(.dateTime.month(.abbreviated)).uppercased())
                .font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
            Text(date.formatted(.dateTime.day()))
                .font(.system(size: 19, weight: .semibold, design: .monospaced)).foregroundStyle(Palette.textPrimary)
        }
        .frame(width: 44)
        .accessibilityElement(children: .combine)
    }
}

/// `.tl` timeline: vertical line with coloured nodes.
enum TimelineTone { case accent, ok, no }

struct TimelineItem<Content: View>: View {
    var tone: TimelineTone = .accent
    var isLast = false
    @ViewBuilder var content: Content

    private var color: Color {
        switch tone {
        case .accent: return Palette.accent
        case .ok: return Palette.okFill
        case .no: return Palette.redFill
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle().strokeBorder(color, lineWidth: 2).background(Circle().fill(Palette.surfaceRaised)).frame(width: 10, height: 10).padding(.top, 3)
                if !isLast { Rectangle().fill(Palette.divider).frame(width: 2).frame(maxHeight: .infinity) }
            }
            .frame(width: 10)
            content.padding(.bottom, isLast ? 0 : 16)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
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

/// App icon tile (`.appicon`) — the official app icon at a given size.
struct AppIconTile: View {
    var size: CGFloat = 44
    var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityLabel("EffiLens")
    }
}


/// Official EffiLens logo (Effilens_Logo → BrandMark) on a white rounded
/// tile — the artwork has a white background, so it is always presented
/// this way on dark or tinted surfaces.
struct BrandLogoTile: View {
    var size: CGFloat = 44
    var glow = false

    var body: some View {
        Image("BrandMark")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .padding(size * 0.06)
            .frame(width: size, height: size)
            .background(Color.white, in: RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
            .shadow(color: glow ? Palette.accent.opacity(0.45) : .black.opacity(0.25), radius: glow ? size * 0.3 : 4, y: glow ? 0 : 2)
            .accessibilityLabel("EffiLens")
    }
}
