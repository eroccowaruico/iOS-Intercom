// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "SoundIsolation",
    platforms: [
        .iOS("26.4"),
        .macOS("26.4"),
    ],
    products: [
        .library(
            name: "SoundIsolation",
            targets: ["SoundIsolation"]
        ),
    ],
    targets: [
        .target(
            name: "SoundIsolation"
        ),
        .testTarget(
            name: "SoundIsolationTests",
            dependencies: ["SoundIsolation"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
