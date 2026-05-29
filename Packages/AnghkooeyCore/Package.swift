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
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")
    ],
    targets: [
        .target(
            name: "AnghkooeyCore",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "AnghkooeyCoreTests",
            dependencies: ["AnghkooeyCore"],
            resources: [.process("Fixtures")]
        )
    ],
    swiftLanguageModes: [.v6]
)
