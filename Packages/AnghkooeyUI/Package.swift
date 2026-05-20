// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AnghkooeyUI",
    platforms: [
        .iOS(.v26),
        .macOS(.v15)
    ],
    products: [
        .library(name: "AnghkooeyUI", targets: ["AnghkooeyUI"])
    ],
    dependencies: [
        .package(path: "../AnghkooeyCore"),
        .package(path: "../AnghkooeyIntelligence")
    ],
    targets: [
        .target(
            name: "AnghkooeyUI",
            dependencies: ["AnghkooeyCore", "AnghkooeyIntelligence"]
            // Strict concurrency enforced implicitly by Swift 6 language mode (.v6).
        ),
        .testTarget(
            name: "AnghkooeyUITests",
            dependencies: ["AnghkooeyUI"]
        )
    ],
    swiftLanguageModes: [.v6]
)
