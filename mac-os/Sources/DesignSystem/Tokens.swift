import SwiftUI
import AppKit

// EffiLens design tokens.
//
// Two authorities (UI_UX_FIDELITY_AUDIT.md §0):
// - Brand colours: BRAND_SPEC.md (navy #022957, amber #FCAC04, light accent
//   #C8912E, dark accent #FCAC04) — these replace the prototype's golds.
// - Layout, sizes, surfaces, status colours, typography scale: the approved
//   EffiLens-macOS-Prototype.html (`:root` / `body.light` CSS variables).

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
    // MARK: Accent (BRAND_SPEC.md)
    static let accent = Color(light: Brand.portalGold, dark: Brand.amber)
    /// Top stop of the primary-button / ring gradient (prototype gold2 → gold).
    static let accentHighlight = Color(light: Color(hex: 0xE2B25C), dark: Color(hex: 0xFFC94A))
    /// Text on an accent fill (prototype `.btn.pri` colour #1b1405).
    static let onAccent = Color(hex: 0x1B1405)
    /// Selection / soft accent fill (prototype `.sb-i.on` = accent 22 %).
    static let accentSoft = Color(light: Brand.portalGold.opacity(0.18), dark: Brand.amber.opacity(0.20))
    static let accentText = Color(light: Color(hex: 0x9A6B17), dark: Color(hex: 0xFFC94A))
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accentHighlight, accent], startPoint: .top, endPoint: .bottom)
    }

    // MARK: Surfaces (prototype --midnight/--navy/--panel, .main, .sidebar, .toolbar, .card)
    /// Main content background (`.main`).
    static let canvas = Color(light: Color(hex: 0xF6F7FB), dark: Color(hex: 0x0B1322))
    /// Sidebar background (`.sidebar`).
    static let sidebar = Color(light: Color(hex: 0xE9EDF4), dark: Color(hex: 0x0E1729))
    /// Toolbar band (`.toolbar`).
    static let toolbar = Color(light: Color(hex: 0xFBFCFE), dark: Color(hex: 0x111C33))
    /// Card fill (`.card`).
    static let surface = Color(light: .white, dark: Color(hex: 0x142035))
    /// Raised panels, popovers, sheets (`--panel`).
    static let surfaceRaised = Color(light: .white, dark: Color(hex: 0x1A2944))
    /// Inset wells: fields, segmented track, list rows (`rgba(0,0,0,.25)` / white).
    static let inset = Color(light: Color(hex: 0xF3F5F9), dark: Color(hex: 0x0A111F))
    /// Settings group fill (`.set-group`).
    static let group = Color(light: .white, dark: Color(hex: 0x131D31))

    // MARK: Text (--text / --text2 / --text3)
    static let textPrimary = Color(light: Color(hex: 0x141B2C), dark: Color(hex: 0xEEF2FA))
    static let textSecondary = Color(light: Color(hex: 0x141B2C, alpha: 0.68), dark: Color(hex: 0xEBF0FA, alpha: 0.66))
    static let textTertiary = Color(light: Color(hex: 0x141B2C, alpha: 0.45), dark: Color(hex: 0xEBF0FA, alpha: 0.42))

    // MARK: Lines (--line / --line2)
    static let hairline = Color(light: Color.black.opacity(0.07), dark: Color.white.opacity(0.08))
    static let divider = Color(light: Color.black.opacity(0.12), dark: Color.white.opacity(0.14))

    // MARK: Status (prototype --ok / --amber / --red / --blue / --violet; light shades deepened for contrast)
    static let success = Color(light: Color(hex: 0x0F8F6E), dark: Color(hex: 0x35C9A0))
    static let warning = Color(light: Color(hex: 0xA66F00), dark: Color(hex: 0xF7C95B))
    static let danger = Color(light: Color(hex: 0xD93A33), dark: Color(hex: 0xFF8A84))
    static let info = Color(light: Color(hex: 0x2F6FD6), dark: Color(hex: 0x7FB0FF))
    static let violet = Color(light: Color(hex: 0x7A55D0), dark: Color(hex: 0xC3A6FF))
    /// Solid status fills (dots, toggles, badges).
    static let okFill = Color(hex: 0x35C9A0)
    static let redFill = Color(hex: 0xFF5F57)
    static let blueFill = Color(hex: 0x4D91FF)
    static let violetFill = Color(hex: 0xA17BEE)

    /// Chart series order.
    static let chartSeries: [Color] = [accent, blueFill, okFill, violetFill, redFill]
}

/// Spacing scale (prototype paddings: 4 · 8 · 10 · 12 · 14 · 16 · 22 · 24).
enum Space {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let grid: CGFloat = 14      // `.grid` gap
    static let l: CGFloat = 16         // card padding
    static let xl: CGFloat = 24        // content horizontal padding
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
}

/// Corner radii (prototype).
enum Radius {
    static let control: CGFloat = 7    // .btn, .field
    static let row: CGFloat = 8        // .cal .d, segmented track
    static let task: CGFloat = 10      // .task, .perm
    static let group: CGFloat = 12     // .set-group
    static let card: CGFloat = 14      // .card, .win
    static let sheet: CGFloat = 14
}

/// Window and chrome metrics (prototype).
enum Metrics {
    static let mainWindow = CGSize(width: 1200, height: 780)
    static let mainWindowMin = CGSize(width: 1000, height: 560)
    static let onboardingWindow = CGSize(width: 820, height: 560)
    static let sidebarWidth: CGFloat = 228
    static let toolbarHeight: CGFloat = 52
    static let onboardingArtWidth: CGFloat = 340
    static let controlHeight: CGFloat = 26
    static let controlHeightLarge: CGFloat = 34
    static let fieldHeight: CGFloat = 30
    static let contentPadding = EdgeInsets(top: 22, leading: 24, bottom: 40, trailing: 24)
}

/// Type scale — SF Pro / SF Mono at the prototype's sizes.
enum Typo {
    static let hero = Font.system(size: 38, weight: .regular)            // .hero-t
    static let display = Font.system(size: 34, weight: .regular)         // onboarding h1
    static let pageTitle = Font.system(size: 30, weight: .regular)       // detail / member / about titles
    static let title = Font.system(size: 20, weight: .semibold)
    static let toolbarTitle = Font.system(size: 15, weight: .bold)
    static let heading = Font.system(size: 15, weight: .semibold)
    static let cardHeader = Font.system(size: 12, weight: .semibold)     // .card h4
    static let body = Font.system(size: 13)
    static let bodyEmphasis = Font.system(size: 13, weight: .semibold)
    static let label = Font.system(size: 11.5, weight: .medium)          // label.lbl
    static let caption = Font.system(size: 11.5)
    static let small = Font.system(size: 11)
    static let overline = Font.system(size: 11, weight: .semibold)       // .sb-h, th
    static let kpi = Font.system(size: 26, weight: .semibold, design: .monospaced)
    static let kpiSuffix = Font.system(size: 12)
    static let timerHero = Font.system(size: 56, weight: .medium, design: .monospaced)   // .timer-big
    static let timerMedium = Font.system(size: 34, weight: .semibold, design: .monospaced)
    static let timerCompact = Font.system(size: 22, weight: .semibold, design: .monospaced)
    static let mono = Font.system(size: 13, design: .monospaced)
}

/// Motion: restrained, honours Reduce Motion at call sites.
enum Motion {
    static let quick = Animation.easeOut(duration: 0.18)
    static let standard = Animation.spring(response: 0.35, dampingFraction: 0.85)
    static let ring = Animation.easeInOut(duration: 0.6)
}
