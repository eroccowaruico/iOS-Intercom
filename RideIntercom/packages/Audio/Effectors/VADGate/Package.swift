// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "VADGate",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
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
