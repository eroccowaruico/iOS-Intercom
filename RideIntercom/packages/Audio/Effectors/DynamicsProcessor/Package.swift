// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "DynamicsProcessor",
    platforms: [
        .iOS("26.4"),
        .macOS("26.4"),
    ],
    products: [
        .library(
            name: "DynamicsProcessor",
            targets: ["DynamicsProcessor"]
        ),
    ],
    targets: [
        .target(
            name: "DynamicsProcessor"
        ),
        .testTarget(
            name: "DynamicsProcessorTests",
            dependencies: ["DynamicsProcessor"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
