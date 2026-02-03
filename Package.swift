// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IntercomCore",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "IntercomCore", targets: ["IntercomCore"])
    ],
    targets: [
        .target(name: "IntercomCore")
    ]
)
