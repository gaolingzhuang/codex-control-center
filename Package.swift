// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexControlCenter",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CodexControlCenter", targets: ["CodexControlCenterApp"])
    ],
    targets: [
        .target(name: "CodexControlCenterCore", path: "Sources/CodexControlCenter"),
        .executableTarget(
            name: "CodexControlCenterApp",
            dependencies: ["CodexControlCenterCore"],
            path: "Sources/CodexControlCenterApp"
        ),
        .testTarget(
            name: "CodexControlCenterTests",
            dependencies: ["CodexControlCenterCore"]
        )
    ]
)
