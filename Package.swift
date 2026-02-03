// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Intercom",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "IntercomCore", targets: ["IntercomCore"]),
        .executable(name: "IntercomApp", targets: ["IntercomApp"])
    ],
    targets: [
        .target(name: "IntercomCore"),
        .executableTarget(
            name: "IntercomApp",
            dependencies: ["IntercomCore"],
            path: "Sources/IntercomApp"
        )
    ]
)
