// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AnghkooeyCore",
    platforms: [
        .iOS(.v26),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "AnghkooeyCore",
            targets: ["AnghkooeyCore"]
        )
    ],
    targets: [
        .target(
            name: "AnghkooeyCore"
        ),
        .testTarget(
            name: "AnghkooeyCoreTests",
            dependencies: ["AnghkooeyCore"],
            resources: [.process("Fixtures")]
        )
    ],
    // Strict concurrency is enforced implicitly by Swift 6 language mode (.v6).
    // No .enableExperimentalFeature("StrictConcurrency") is needed.
    swiftLanguageModes: [.v6]
)
