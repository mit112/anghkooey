// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AnghkooeyIntelligence",
    platforms: [
        .iOS(.v26),
        .macOS(.v15)
    ],
    products: [
        .library(name: "AnghkooeyIntelligence", targets: ["AnghkooeyIntelligence"])
    ],
    dependencies: [
        .package(path: "../AnghkooeyCore")
    ],
    targets: [
        .target(
            name: "AnghkooeyIntelligence",
            dependencies: ["AnghkooeyCore"]
            // Strict concurrency enforced implicitly by Swift 6 language mode (.v6).
        ),
        .testTarget(
            name: "AnghkooeyIntelligenceTests",
            dependencies: ["AnghkooeyIntelligence"]
        )
    ],
    swiftLanguageModes: [.v6]
)
