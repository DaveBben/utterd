// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Libraries",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "Core", targets: ["Core"]),
    ],
    dependencies: [
        // Add third-party SPM dependencies here
    ],
    targets: [
        .target(
            name: "Core",
            dependencies: [],
            path: "Sources/Core"
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core"],
            path: "Tests/CoreTests"
        ),
    ]
)
