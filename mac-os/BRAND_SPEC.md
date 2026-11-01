# EffiLens Brand Spec (macOS)

**Sources of truth (only):**
1. Official logo files — `C:\AIML Tasks\Workpulse\Effilens_Logo\` (3 PNG 1080², 3 ICO 32²).
2. Production portal implementation — `frontend/src/lib/design-tokens.ts` (+ `LANDING` palette).

**Explicitly NOT used for brand values:** `EffiLens-macOS-Prototype.html` (UI/UX only), `CLAUDE.md` design table, and the Tauri app's "Instrument" theme (`workpulse-rust/CLAUDE.md`: Fraunces / Public Sans / gold) — three mutually inconsistent sources.

Legend: ✅ verified from source · 🔶 INFERRED — needs brand-owner confirmation.

## 1. Logo assets

| Asset | File | Use |
|---|---|---|
| Mark (lens "E") | `Efflens_Logo_ (3).png` → `BrandMark`, `AppIcon` | App icon, menu-bar popover, launch, small brand moments |
| Wordmark | `Efflens_Logo_ (2).png` → `BrandWordmark` | Onboarding brand panel |
| Lockup (mark + wordmark) | `Efflens_Logo_ (1).png` → `BrandLockup` | About window, DMG background |

Rules: originals untouched (copied into the asset catalogue). Minimum mark size 16 pt; clear space ≥ ¼ mark width. Never recolour, outline, add gradients or shadows. 🔶 No vector (SVG/PDF) master exists — request one; raster 1080² is acceptable up to 512 pt @2x. 🔶 The mark PNG has a white background; a transparent macOS-style icon (rounded-rect safe area) should be produced by the brand owner.

## 2. Colour

| Token | Light | Dark | Source |
|---|---|---|---|
| Brand navy | `#022957` | same | ✅ sampled from wordmark "Effi" (matches portal `LANDING.navy #0b2a5b`) |
| Brand amber | `#FCAC04` | same | ✅ sampled from wordmark "lens" (matches `LANDING.gold #f5a800`) |
| Accent (interactive) | `#C8912E` | `#FCAC04` 🔶 | ✅ portal `PRIMARY`; dark value inferred (portal has no dark theme) |
| On-accent text | `#FFFFFF` | `#1A1405` 🔶 | ✅ portal `BTN_PRIMARY_TEXT` |
| Canvas | `#F0F2F7` | `#0F1628` 🔶 | ✅ `BG_BASE` / `HERO_CARD_BG_2` |
| Surface | `#FFFFFF` | `#1A2035` 🔶 | ✅ `BG_SURFACE` / `SIDEBAR_BG` |
| Surface raised | `#FFFFFF` | `#232B44` 🔶 | ✅ `SIDEBAR_BG_2` |
| Inset | `#F8F9FC` | `#141A2C` 🔶 | ✅ `BG_EMPTY` |
| Text 1/2/3 | `#1A2035` @1/.65/.45 | `#F0F4FF` @1/.65/.45 | ✅ `TEXT_*`, `SIDEBAR_TEXT_*` (tertiary raised .40→.45 for contrast 🔶) |
| Hairline / divider | navy @.08/.12 | white @.08/.12 | ✅ `CARD_BORDER`, `SIDEBAR_BORDER` |
| Success | `#16A34A` 🔶 | `#22C55E` | ✅ `GREEN` (light deepened for 4.5:1) |
| Warning | `#B7791F` 🔶 | `#FBBF24` | ✅ `AMBER` |
| Danger | `#DC2626` 🔶 | `#F87171` | ✅ `RED` |
| Info | `#0284C7` 🔶 | `#38BDF8` | ✅ `SKY` |
| Chart series | accent, success, info, warning, danger | | ✅ `CHART_SERIES_COLORS` |

Rules: one accent. Status colours only for status. No purple/violet (portal keeps `VIOLET` only for legacy specifics). No gradients on UI chrome.

## 3. Typography

| Role | macOS | Portal equivalent |
|---|---|---|
| Display 26 semibold, Title 20, Heading 15 | SF Pro (system) | Inter ✅ |
| Body 13, Caption 11.5, Overline 10.5 small-caps | SF Pro | Inter |
| Live numerals (timers, KPIs) | SF Mono / monospaced digits | JetBrains Mono ✅ |

🔶 Inter is the portal's brand face; native macOS convention (and the design-skill rule against Inter on Apple platforms) favours SF Pro. Proposal: SF Pro in-app, Inter permitted in marketing/DMG art. Needs confirmation. No serif display face exists in official brand sources, so the prototype's serif headings are not adopted.

## 4. Spacing, radii, shadows

- Spacing (8-pt grid): 2 · 4 · 8 · 12 · 16 · 24 · 32 · 48.
- Radii 🔶: control 6 · row 8 · card 12 · sheet 16 (portal uses Ant Design defaults; aligned to grid).
- Shadow: cards `black @4%, r10, y3` (portal `CARD_SHADOW` ≈ navy @4%, 20 px). Sheets `@8%, r24, y8`.

## 5. Iconography

SF Symbols only (outline weight in sidebar, `.fill` for state). No emoji. Status dots: running = success, paused/break = warning, offline = tertiary.

## 6. Components

Card (surface + hairline + soft shadow, no accent stripe) · StatTile (overline, mono value, footnote, optional progress) · StatusPill (tone @14% bg) · ProgressRing (signature element: live session) · InitialsAvatar (brand navy) · BrandMark · Loadable states (`ProgressView`, `ContentUnavailableView` empty/error).

## 7. Light & dark

Both supported (prototype requirement). Light mirrors the production portal; dark derives from portal navy surfaces 🔶. Sidebar uses native vibrancy (macOS convention) instead of the portal's forced dark navy sidebar — 🔶 confirm.

## 8. Open confirmations

1. Dark accent `#FCAC04` vs `#C8912E`. 2. SF Pro vs Inter. 3. Vector logo + transparent app icon. 4. Native sidebar vs navy sidebar.
