// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AnghkooeyIntelligence",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(name: "AnghkooeyIntelligence", targets: ["AnghkooeyIntelligence"]),
        .executable(name: "EvalRunner", targets: ["EvalRunner"])
    ],
    dependencies: [
        .package(path: "../AnghkooeyCore"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "AnghkooeyIntelligence",
            dependencies: ["AnghkooeyCore"]
        ),
        .executableTarget(
            name: "EvalRunner",
            dependencies: [
                "AnghkooeyIntelligence",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/EvalRunner"
        ),
        .testTarget(
            name: "AnghkooeyIntelligenceTests",
            dependencies: ["AnghkooeyIntelligence"],
            resources: [.process("Fixtures")]
        )
    ],
    swiftLanguageModes: [.v6]
)
