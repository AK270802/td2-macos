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
    // MARK: Accent — prototype --gold / --gold2 (user instruction 2026-11-02:
    // "match exactly as prototype"; supersedes BRAND_SPEC accent hexes).
    static let accent = Color(hex: 0xD5A04A)
    /// Top stop of the primary-button / ring gradient (--gold2).
    static let accentHighlight = Color(hex: 0xF0C779)
    /// Text on an accent fill (`.btn.pri` colour #1b1405).
    static let onAccent = Color(hex: 0x1B1405)
    /// Selection fill (`.sb-i.on` = rgba(213,160,74,.22)).
    static let accentSoft = Color(hex: 0xD5A04A, alpha: 0.22)
    /// Emphasised text (`<em>`, links) = --gold2 in both appearances.
    static let accentText = Color(hex: 0xF0C779)
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accentHighlight, accent], startPoint: .top, endPoint: .bottom)
    }

    // MARK: Surfaces — translucent layers over `GlassBackdrop` (prototype
    // .win glass, .sidebar, .main, .toolbar, .card, .set-group).
    static let canvas = Color(light: Color(hex: 0xFAFBFE, alpha: 0.70), dark: Color(hex: 0x080E1C, alpha: 0.55))
    static let sidebar = Color(light: Color(hex: 0xEBEEF5, alpha: 0.45), dark: Color(hex: 0x0A1224, alpha: 0.35))
    static let toolbar = Color(light: Color.white.opacity(0.5), dark: Color(hex: 0x101B32, alpha: 0.35))
    /// Card fill (`.card`: white 85 % light; white 5.5 %→2 % gradient dark).
    static let surface = Color(light: Color.white.opacity(0.85), dark: Color.white.opacity(0.035))
    /// Popovers, sheets, alerts (`--panel` / `.alert`).
    static let surfaceRaised = Color(light: Color(hex: 0xF5F5F8), dark: Color(hex: 0x1A2944))
    /// Inset wells (`.field`: rgba(0,0,0,.25) dark / white light).
    static let inset = Color(light: .white, dark: Color.black.opacity(0.25))
    /// Settings group (`.set-group` rgba(255,255,255,.035)).
    static let group = Color(light: Color.white.opacity(0.6), dark: Color.white.opacity(0.035))

    // MARK: Text (--text / --text2 / --text3)
    static let textPrimary = Color(light: Color(hex: 0x141B2C), dark: Color(hex: 0xEEF2FA))
    static let textSecondary = Color(light: Color(hex: 0x141B2C, alpha: 0.68), dark: Color(hex: 0xEBF0FA, alpha: 0.66))
    static let textTertiary = Color(light: Color(hex: 0x141B2C, alpha: 0.42), dark: Color(hex: 0xEBF0FA, alpha: 0.42))

    // MARK: Lines (--line / --line2)
    static let hairline = Color(light: Color.black.opacity(0.07), dark: Color.white.opacity(0.08))
    static let divider = Color(light: Color.black.opacity(0.12), dark: Color.white.opacity(0.14))

    // MARK: Status — prototype pill text colours (same in both appearances)
    static let success = Color(hex: 0x35C9A0)       // --ok
    static let warning = Color(hex: 0xF7C95B)       // .pill.wait
    static let danger = Color(hex: 0xFF8A84)        // .pill.no
    static let info = Color(hex: 0x7FB0FF)          // .pill.blue
    static let violet = Color(hex: 0xC3A6FF)        // .pill.vio
    /// Solid status fills (dots, toggles, badges).
    static let okFill = Color(hex: 0x35C9A0)
    static let redFill = Color(hex: 0xFF5F57)
    static let blueFill = Color(hex: 0x4D91FF)
    static let violetFill = Color(hex: 0xA17BEE)
    static let amberFill = Color(hex: 0xFEBC2E)

    /// Chart series order.
    static let chartSeries: [Color] = [blueFill, violetFill, okFill, accent, textTertiary]
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
    // Display face: Instrument Serif (OFL, bundled in Resources/Fonts,
    // registered via ATSApplicationFontsPath) — prototype `--serif`.
    static func serif(_ size: CGFloat) -> Font { .custom("InstrumentSerif-Regular", size: size) }
    static func serifItalic(_ size: CGFloat) -> Font { .custom("InstrumentSerif-Italic", size: size) }
    static let hero = serif(38)               // .hero-t
    static let display = serif(34)            // onboarding h1
    static let pageTitle = serif(30)          // detail / member titles
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
