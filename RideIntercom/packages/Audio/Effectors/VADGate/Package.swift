// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "VADGate",
    platforms: [
        .iOS("26.4"),
        .macOS("26.4"),
    ],
    products: [
        .library(
            name: "VADGate",
            targets: ["VADGate"]
        ),
    ],
    targets: [
        .target(
            name: "VADGate"
        ),
        .testTarget(
            name: "VADGateTests",
            dependencies: ["VADGate"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
