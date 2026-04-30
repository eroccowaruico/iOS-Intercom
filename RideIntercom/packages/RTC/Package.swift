// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RTC",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .macCatalyst(.v17),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "RTC",
            targets: ["RTC"]
        ),
        .library(
            name: "RTCNativeWebRTC",
            targets: ["RTCNativeWebRTC"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "RTC"
        ),
        .target(
            name: "RTCNativeWebRTC",
            dependencies: [
                "RTC",
                "WebRTC",
            ]
        ),
        .binaryTarget(
            name: "WebRTC",
            path: "BinaryArtifacts/WebRTC/WebRTC.xcframework.zip"
        ),
        .testTarget(
            name: "RTCTests",
            dependencies: ["RTC"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
