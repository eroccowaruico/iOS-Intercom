// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "AudioMixer",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "AudioMixer",
            targets: ["AudioMixer"]
        ),
    ],
    targets: [
        .target(
            name: "AudioMixer"
        ),
        .testTarget(
            name: "AudioMixerTests",
            dependencies: ["AudioMixer"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
