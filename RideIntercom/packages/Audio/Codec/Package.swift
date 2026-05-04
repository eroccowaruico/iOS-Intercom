// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Codec",
    platforms: [
        .iOS("26.4"),
        .macOS("26.4"),
    ],
    products: [
        .library(
            name: "Codec",
            targets: ["Codec"]
        ),
    ],
    targets: [
        .target(
            name: "Codec"
        ),
        .testTarget(
            name: "CodecTests",
            dependencies: ["Codec"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
