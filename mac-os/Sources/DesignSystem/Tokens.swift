import SwiftUI
import AppKit

// EffiLens design tokens. Source of truth: BRAND_SPEC.md.
//
// Provenance (strict): official logo files (Effilens_Logo/) and the
// production portal tokens (frontend/src/lib/design-tokens.ts). Neither the
// HTML prototype nor CLAUDE.md supplies brand values. Values marked
// INFERRED are pending brand-owner confirmation.

extension Color {
    /// Appearance-adaptive colour (light / dark).
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua]) != nil
            return NSColor(isDark ? dark : light)
        })
    }

    /// `Color(hex: 0xRRGGBB, alpha:)`.
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

enum Brand {
    /// Logo wordmark navy ("Effi") — sampled from Efflens_Logo_ (2).png.
    static let navy = Color(hex: 0x022957)
    /// Logo wordmark amber ("lens") — sampled from Efflens_Logo_ (2).png.
    static let amber = Color(hex: 0xFCAC04)
    /// Portal primary accent (`PRIMARY`, design-tokens.ts).
    static let portalGold = Color(hex: 0xC8912E)
    /// Portal sidebar / hero navy (`SIDEBAR_BG`).
    static let portalNavy = Color(hex: 0x1A2035)
}

enum Palette {
    // MARK: Accent
    /// Interactive accent. Light: portal PRIMARY. Dark: logo amber (INFERRED — portal has no dark theme).
    static let accent = Color(light: Brand.portalGold, dark: Brand.amber)
    /// Text/icon colour placed on an accent fill (portal uses white on gold).
    static let onAccent = Color(light: .white, dark: Color(hex: 0x1A1405))
    static let accentSoft = Color(light: Brand.portalGold.opacity(0.12), dark: Brand.amber.opacity(0.16))

    // MARK: Surfaces (portal BG_BASE / BG_SURFACE / BG_EMPTY; dark INFERRED from SIDEBAR_BG, SIDEBAR_BG_2, HERO_CARD_BG_2)
    static let canvas = Color(light: Color(hex: 0xF0F2F7), dark: Color(hex: 0x0F1628))
    static let surface = Color(light: .white, dark: Color(hex: 0x1A2035))
    static let surfaceRaised = Color(light: .white, dark: Color(hex: 0x232B44))
    static let inset = Color(light: Color(hex: 0xF8F9FC), dark: Color(hex: 0x141A2C))

    // MARK: Text (portal TEXT_1/2/3; dark = SIDEBAR_TEXT_1/2/3)
    static let textPrimary = Color(light: Color(hex: 0x1A2035), dark: Color(hex: 0xF0F4FF))
    static let textSecondary = Color(light: Color(hex: 0x1A2035, alpha: 0.65), dark: Color(hex: 0xF0F4FF, alpha: 0.65))
    static let textTertiary = Color(light: Color(hex: 0x1A2035, alpha: 0.45), dark: Color(hex: 0xF0F4FF, alpha: 0.45))

    // MARK: Lines (portal CARD_BORDER / SIDEBAR_BORDER)
    static let hairline = Color(light: Color(hex: 0x1A2035, alpha: 0.08), dark: Color.white.opacity(0.08))
    static let divider = Color(light: Color(hex: 0x1A2035, alpha: 0.12), dark: Color.white.opacity(0.12))

    // MARK: Semantic status (portal GREEN / AMBER / RED / SKY)
    static let success = Color(light: Color(hex: 0x16A34A), dark: Color(hex: 0x22C55E))   // light shade deepened for 4.5:1 text contrast (INFERRED)
    static let warning = Color(light: Color(hex: 0xB7791F), dark: Color(hex: 0xFBBF24))   // INFERRED light shade
    static let danger = Color(light: Color(hex: 0xDC2626), dark: Color(hex: 0xF87171))    // INFERRED light shade
    static let info = Color(light: Color(hex: 0x0284C7), dark: Color(hex: 0x38BDF8))      // INFERRED light shade

    /// Chart series order (portal `CHART_SERIES_COLORS`).
    static let chartSeries: [Color] = [accent, success, info, warning, danger]
}

/// 8-pt spacing grid.
enum Space {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
}

/// Corner radii (INFERRED — portal radii are Ant Design defaults; aligned to the 8-pt grid).
enum Radius {
    static let control: CGFloat = 6
    static let row: CGFloat = 8
    static let card: CGFloat = 12
    static let sheet: CGFloat = 16
}

/// Type scale. Brand body face is Inter on the web; on macOS the native
/// equivalent SF Pro is used (BRAND_SPEC.md §Typography — pending confirmation).
/// Numerals that update live (timers, KPIs) use SF Mono / monospaced digits,
/// mirroring the portal's JetBrains Mono usage.
enum Typo {
    static let display = Font.system(size: 26, weight: .semibold)
    static let title = Font.system(size: 20, weight: .semibold)
    static let heading = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 13)
    static let bodyEmphasis = Font.system(size: 13, weight: .medium)
    static let caption = Font.system(size: 11.5)
    static let overline = Font.system(size: 10.5, weight: .semibold).smallCaps()
    static let kpi = Font.system(size: 26, weight: .semibold, design: .monospaced)
    static let timerHero = Font.system(size: 52, weight: .medium, design: .monospaced)
    static let timerCompact = Font.system(size: 13, weight: .medium, design: .monospaced)
}

/// Motion: restrained, honours Reduce Motion at call sites.
enum Motion {
    static let quick = Animation.easeOut(duration: 0.18)
    static let standard = Animation.spring(response: 0.35, dampingFraction: 0.85)
    static let ring = Animation.easeInOut(duration: 0.6)
}
