// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "PeakLimiter",
    platforms: [
        .iOS("26.4"),
        .macOS("26.4"),
    ],
    products: [
        .library(
            name: "PeakLimiter",
            targets: ["PeakLimiter"]
        ),
    ],
    targets: [
        .target(
            name: "PeakLimiter"
        ),
        .testTarget(
            name: "PeakLimiterTests",
            dependencies: ["PeakLimiter"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
