// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "SessionManager",
    platforms: [
        .iOS("26.4"),
        .macOS("26.4"),
    ],
    products: [
        .library(
            name: "SessionManager",
            targets: ["SessionManager"]
        ),
    ],
    targets: [
        .target(
            name: "SessionManager"
        ),
        .testTarget(
            name: "SessionManagerTests",
            dependencies: ["SessionManager"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
