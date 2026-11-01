// swift-tools-version:5.10
// EffiLensKit — UI-independent core of the native EffiLens macOS app:
// networking, Codable models mirroring core-services Pydantic schemas,
// session/Keychain handling and the local agent IPC client.
// The SwiftUI app target (project.yml) depends on this package so that the
// core can be unit-tested headlessly with `swift test` on macOS runners.
import PackageDescription

let package = Package(
    name: "EffiLensKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EffiLensKit", targets: ["EffiLensKit"]),
    ],
    targets: [
        .target(
            name: "EffiLensKit",
            path: "Sources/EffiLensKit",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "EffiLensKitTests",
            dependencies: ["EffiLensKit"],
            path: "Tests/EffiLensKitTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
