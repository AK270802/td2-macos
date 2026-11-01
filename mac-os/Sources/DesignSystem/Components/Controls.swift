import SwiftUI

// Controls specified by the prototype CSS (`.btn`, `.field`, `label.lbl`,
// `.seg`, `.tog`, `.set-group`/`.set-row`, `table`, `.bars`, `.task`).

// MARK: - Buttons (.btn / .btn.pri / .btn.dan / .btn.blue / .btn.lg)

struct EffiButtonStyle: ButtonStyle {
    enum Kind { case normal, primary, danger, blue }
    enum Size { case regular, large }
    var kind: Kind = .normal
    var size: Size = .regular
    var fullWidth = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        let radius: CGFloat = size == .large ? 9 : Radius.control
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return configuration.label
            .font(.system(size: size == .large ? 14 : 13, weight: kind == .primary ? .semibold : .medium))
            .lineLimit(1)
            .padding(.horizontal, size == .large ? 20 : 14)
            .frame(height: size == .large ? Metrics.controlHeightLarge : Metrics.controlHeight)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .foregroundStyle(foreground)
            .background(background, in: shape)
            .overlay(shape.strokeBorder(border, lineWidth: 0.5))
            .shadow(color: .black.opacity(kind == .normal ? 0.15 : 0), radius: 0.5, y: 1)
            .brightness(configuration.isPressed ? -0.12 : 0)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(shape)
    }

    private var foreground: Color {
        switch kind {
        case .normal: return Palette.textPrimary
        case .primary: return Palette.onAccent
        case .danger: return Palette.danger
        case .blue: return .white
        }
    }

    private var background: AnyShapeStyle {
        switch kind {
        case .normal: return AnyShapeStyle(scheme == .dark ? Color.white.opacity(0.10) : Color.white)
        case .primary: return AnyShapeStyle(Palette.accentGradient)
        case .danger: return AnyShapeStyle(Palette.redFill.opacity(0.16))
        case .blue: return AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x5C9CFF), Color(hex: 0x2F78F0)], startPoint: .top, endPoint: .bottom))
        }
    }

    private var border: Color {
        kind == .normal ? (scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.12)) : .clear
    }
}

extension ButtonStyle where Self == EffiButtonStyle {
    static var effi: EffiButtonStyle { EffiButtonStyle() }
    static var effiPrimary: EffiButtonStyle { EffiButtonStyle(kind: .primary) }
    static var effiDanger: EffiButtonStyle { EffiButtonStyle(kind: .danger) }
    static func effiButton(_ kind: EffiButtonStyle.Kind, _ size: EffiButtonStyle.Size = .regular, fullWidth: Bool = false) -> EffiButtonStyle {
        EffiButtonStyle(kind: kind, size: size, fullWidth: fullWidth)
    }
}

/// Toolbar icon button (`.tb-btn`): 30 × 28, secondary tint, optional red pip.
struct ToolbarIconButton: View {
    let symbol: String
    let help: String
    var showsPip = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 30, height: 28)
                .overlay(alignment: .topTrailing) {
                    if showsPip { Circle().fill(Palette.redFill).frame(width: 7, height: 7).offset(x: -5, y: 4) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Fields (.field, label.lbl)

struct EffiFieldBackground: ViewModifier {
    var focused = false
    var height: CGFloat? = Metrics.fieldHeight
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        content
            .padding(.horizontal, 10)
            .frame(height: height)
            .background(scheme == .dark ? Color.black.opacity(0.25) : Color.white, in: shape)
            .overlay(shape.strokeBorder(focused ? Palette.accent : Palette.divider, lineWidth: 1))
            .overlay(shape.stroke(Palette.accent.opacity(focused ? 0.35 : 0), lineWidth: 3.5).padding(-2))
    }
}

/// Plain text field with prototype chrome.
struct EffiTextField: View {
    let placeholder: String
    @Binding var text: String
    var secure = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if secure { SecureField(placeholder, text: $text) } else { TextField(placeholder, text: $text) }
        }
        .textFieldStyle(.plain)
        .font(Typo.body)
        .focused($focused)
        .modifier(EffiFieldBackground(focused: focused))
    }
}

/// Multi-line field (`textarea.field`, 70 pt).
struct EffiTextArea: View {
    let placeholder: String
    @Binding var text: String
    var height: CGFloat = 70
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(Typo.body)
            .lineLimit(3...8)
            .focused($focused)
            .padding(.vertical, 8)
            .frame(minHeight: height, alignment: .topLeading)
            .modifier(EffiFieldBackground(focused: focused, height: nil))
    }
}

/// `label.lbl` — 11.5 pt medium secondary, 12 pt above / 5 pt below.
struct FieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Typo.label).foregroundStyle(Palette.textSecondary)
            .padding(.top, 12).padding(.bottom, 5)
    }
}

/// Picker / date picker wrapped in field chrome.
struct FieldChrome<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(EffiFieldBackground())
    }
}

// MARK: - Segmented (.seg)

struct EffiSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let on = option.0 == selection
                Button {
                    selection = option.0
                } label: {
                    Text(option.1)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(on ? Palette.textPrimary : Palette.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(scheme == .dark ? Color.white.opacity(0.14) : Color.white)
                                    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(scheme == .dark ? Color.black.opacity(0.25) : Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).strokeBorder(Palette.hairline))
        .fixedSize()
    }
}

// MARK: - Toggle (.tog — green when on)

struct EffiToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: Space.s)
            Capsule()
                .fill(configuration.isOn ? Palette.okFill : Palette.textPrimary.opacity(0.18))
                .frame(width: 34, height: 20)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(.white).shadow(color: .black.opacity(0.35), radius: 1.5, y: 1).frame(width: 16, height: 16).padding(2)
                }
                .animation(Motion.quick, value: configuration.isOn)
                .onTapGesture { configuration.isOn.toggle() }
                .accessibilityAddTraits(.isButton)
        }
    }
}

// MARK: - Settings rows (.set-group / .set-row / .set-title)

struct SetGroup<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title).font(Typo.label).fontWeight(.semibold).foregroundStyle(Palette.textTertiary).padding(.horizontal, 4)
            }
            VStack(spacing: 0) { content }
                .background(Palette.group, in: RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.group, style: .continuous).strokeBorder(Palette.hairline))
        }
        .padding(.bottom, Space.l)
    }
}

struct SetRow<Trailing: View>: View {
    let title: String
    var detail: String?
    var isLast = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.m) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Typo.body).foregroundStyle(Palette.textPrimary)
                    if let detail { Text(detail).font(Typo.caption).foregroundStyle(Palette.textTertiary).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: Space.s)
                trailing
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            if !isLast { Divider().overlay(Palette.hairline) }
        }
    }
}

extension SetRow where Trailing == Text {
    init(_ title: String, value: String, isLast: Bool = false) {
        self.title = title
        self.detail = nil
        self.isLast = isLast
        self.trailing = Text(value).font(Typo.body).foregroundStyle(Palette.textSecondary)
    }
}

/// `.set-row` with a `.tog` toggle.
struct SetToggleRow: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool
    var isLast = false

    var body: some View {
        SetRow(title: title, detail: detail, isLast: isLast) {
            Toggle("", isOn: $isOn).toggleStyle(EffiToggleStyle()).labelsHidden().frame(width: 34)
                .accessibilityLabel(title)
        }
    }
}

// MARK: - Table (table / th / td)

/// Lightweight table: 11 pt header, 9/10 cell padding, hairline rows, zebra.
struct EffiTable<Row: Identifiable>: View {
    struct Column {
        let title: String
        var width: CGFloat?
        let cell: (Row) -> AnyView
        init<V: View>(_ title: String, width: CGFloat? = nil, @ViewBuilder cell: @escaping (Row) -> V) {
            self.title = title
            self.width = width
            self.cell = { AnyView(cell($0)) }
        }
    }

    let rows: [Row]
    let columns: [Column]
    var onSelect: ((Row) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                    Text(column.title).font(Typo.overline).foregroundStyle(Palette.textTertiary)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .frame(width: column.width, alignment: .leading)
                        .frame(maxWidth: column.width == nil ? .infinity : nil, alignment: .leading)
                }
            }
            Divider().overlay(Palette.hairline)
            LazyVStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    TableRowView(index: index, onTap: tapHandler(for: row)) {
                        HStack(spacing: 0) {
                            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                                column.cell(row)
                                    .font(Typo.body)
                                    .lineLimit(1)
                                    .padding(.horizontal, 10).padding(.vertical, 9)
                                    .frame(width: column.width, alignment: .leading)
                                    .frame(maxWidth: column.width == nil ? .infinity : nil, alignment: .leading)
                            }
                        }
                    }
                }
            }
        }
    }
}

extension EffiTable {
    fileprivate func tapHandler(for row: Row) -> (() -> Void)? {
        guard let onSelect else { return nil }
        return { onSelect(row) }
    }
}

private struct TableRowView<Content: View>: View {
    let index: Int
    var onTap: (() -> Void)?
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            content
                .background(hovering ? Palette.textPrimary.opacity(0.03) : (index.isMultiple(of: 2) ? .clear : Palette.textPrimary.opacity(0.015)))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .onTapGesture { onTap?() }
            Divider().overlay(Palette.hairline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
    }
}

// MARK: - Bars chart (.bars)

struct BarsChart: View {
    struct Bar: Identifiable {
        let id = UUID()
        let label: String
        let value: Double
        var valueText: String?
        var highlighted = true
    }

    let bars: [Bar]
    var maxValue: Double?
    var height: CGFloat = 140
    var gradient: [Color] = [Palette.accentHighlight, Palette.accent]

    var body: some View {
        let top = maxValue ?? max(bars.map(\.value).max() ?? 1, 0.0001)
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(bars) { bar in
                VStack(spacing: 6) {
                    Spacer(minLength: 0)
                    Text(bar.valueText ?? "").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Palette.textSecondary)
                    UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 3, bottomTrailingRadius: 3, topTrailingRadius: 6, style: .continuous)
                        .fill(LinearGradient(colors: gradient, startPoint: .top, endPoint: .bottom))
                        .opacity(bar.highlighted ? 1 : 0.55)
                        .frame(maxWidth: 34)
                        .frame(height: max(2, (height - 36) * CGFloat(min(bar.value / top, 1))))
                    Text(bar.label).font(.system(size: 10.5)).foregroundStyle(Palette.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(bar.label): \(bar.valueText ?? String(bar.value))")
            }
        }
        .frame(height: height)
        .padding(.top, 10)
    }
}

// MARK: - Task row (.task / .task.sel)

struct TaskRowCard<Trailing: View>: View {
    let title: String
    let subtitle: String
    var dot: Color = Palette.accent
    var selected = false
    @ViewBuilder var trailing: Trailing
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(dot).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Typo.body).foregroundStyle(Palette.textPrimary).lineLimit(1)
                Text(subtitle).font(Typo.small).foregroundStyle(Palette.textTertiary).lineLimit(1)
            }
            Spacer(minLength: Space.s)
            trailing
        }
        .padding(12)
        .background(selected ? Palette.accent.opacity(0.08) : Palette.textPrimary.opacity(0.02),
                    in: RoundedRectangle(cornerRadius: Radius.task, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.task, style: .continuous)
            .strokeBorder(selected ? Palette.accent : (hovering ? Palette.divider : Palette.hairline)))
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
    }
}

// MARK: - Page scaffold

/// Scrollable page with the prototype content padding (22 / 24 / 40).
struct Page<Content: View>: View {
    var maxWidth: CGFloat? = nil
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.grid) { content }
                .frame(maxWidth: maxWidth ?? .infinity, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: maxWidth == nil ? .topLeading : .top)
                .padding(Metrics.contentPadding)
        }
        .scrollContentBackground(.hidden)
    }
}

/// Two-column grid with a fractional ratio (prototype `grid-template-columns: a fr b fr`).
/// Pass exactly two views in the closure: left, then right.
struct FractionalColumns<Content: View>: View {
    var ratio: CGFloat = 1.3
    @ViewBuilder var content: Content

    var body: some View {
        RatioRow(ratio: ratio, spacing: Space.grid) { content }
    }
}

/// Lays out two subviews side by side, widths in `ratio : 1`, height = tallest.
struct RatioRow: Layout {
    var ratio: CGFloat
    var spacing: CGFloat

    private func widths(_ total: CGFloat) -> (CGFloat, CGFloat) {
        let available = max(total - spacing, 0)
        return (available * ratio / (ratio + 1), available / (ratio + 1))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 900
        let (a, b) = widths(total)
        let ws = [a, b]
        var height: CGFloat = 0
        for (i, sub) in subviews.prefix(2).enumerated() {
            height = max(height, sub.sizeThatFits(ProposedViewSize(width: ws[i], height: nil)).height)
        }
        return CGSize(width: total, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (a, b) = widths(bounds.width)
        let ws = [a, b]
        var x = bounds.minX
        for (i, sub) in subviews.prefix(2).enumerated() {
            sub.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(width: ws[i], height: bounds.height))
            x += ws[i] + spacing
        }
    }
}

/// Equal-width grid (`.g2` / `.g3` / `.g4`).
struct EqualColumns<Content: View>: View {
    let count: Int
    var spacing: CGFloat = Space.grid
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: count),
                  alignment: .leading, spacing: spacing) {
            content
        }
    }
}

/// `.hero-t` with an accent-coloured emphasised word (prototype `<em>`).
struct HeroTitle: View {
    let prefix: String
    let emphasis: String
    var suffix: String = ""
    var font: Font = Typo.hero

    var body: some View {
        (Text(prefix) + Text(emphasis).foregroundColor(Palette.accentText) + Text(suffix))
            .font(font)
            .tracking(-0.3)
            .foregroundStyle(Palette.textPrimary)
            .lineSpacing(0)
    }
}

/// Uppercase overline (dashboard date line).
struct Overline: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.66).foregroundStyle(Palette.textTertiary)
    }
}
