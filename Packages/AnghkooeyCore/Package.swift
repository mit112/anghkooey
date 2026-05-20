// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AnghkooeyCore",
    platforms: [
        .iOS(.v26)
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
            dependencies: ["AnghkooeyCore"]
        )
    ],
    swiftLanguageModes: [.v6]
)
