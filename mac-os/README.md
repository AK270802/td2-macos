# EffiLens for macOS (native SwiftUI)

Native macOS client for EffiLens/WorkPulse. Coexists with — and does not modify — the Tauri app (`../app`), the Rust agent (`../agentd`, `../common`), the Windows go-agent, the portal and core-services.

```
mac-os/
├── project.yml              XcodeGen spec (generates EffiLens.xcodeproj on macOS)
├── Package.swift            EffiLensKit package (UI-free core + tests)
├── Sources/
│   ├── EffiLensKit/         Core · Networking · Models · Auth · Storage · Services · Agent
│   ├── App/                 EffiLensApp, AppEnvironment (DI), AppModel, Route, RootView
│   ├── DesignSystem/        Tokens (brand), Formatting, Components
│   └── Features/            Onboarding · Shell · Dashboard · Leave · MenuBar
├── Resources/               Info.plist, entitlements, Assets.xcassets (official logo)
├── Tests/EffiLensKitTests/  Decoding, API client, fixtures
├── Scripts/                 build.sh, release.sh
└── *.md                     Architecture & plan documents
```

Docs: [ARCHITECTURE](ARCHITECTURE.md) · [IMPLEMENTATION_PLAN](IMPLEMENTATION_PLAN.md) · [BRAND_SPEC](BRAND_SPEC.md) · [SCREEN_INVENTORY](SCREEN_INVENTORY.md) · [API_INTEGRATION](API_INTEGRATION.md) · [RUST_AGENT_INTEGRATION](RUST_AGENT_INTEGRATION.md) · [SECURITY_AND_PRIVACY](SECURITY_AND_PRIVACY.md) · [BUILD_AND_RELEASE](BUILD_AND_RELEASE.md) · [DECISIONS_AND_ASSUMPTIONS](DECISIONS_AND_ASSUMPTIONS.md)

Build: see BUILD_AND_RELEASE.md. **Not yet compiled** — first verification happens on the `macos-native` GitHub Actions workflow.
