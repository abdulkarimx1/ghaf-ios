// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "GhafCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "GhafCore",
            targets: ["GhafCore"]
        )
    ],
    targets: [
        .target(
            name: "GhafCore"
        ),
        .testTarget(
            name: "GhafCoreTests",
            dependencies: ["GhafCore"]
        )
    ]
)
