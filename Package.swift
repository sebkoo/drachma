// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "drachma",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DrachmaCore", targets: ["DrachmaCore"]),
        .executable(name: "drachma-mcp", targets: ["DrachmaMCP"]),
    ],
    targets: [
        .target(
            name: "DrachmaCore",
            path: "DrachmaCore/Sources"
        ),
        .testTarget(
            name: "DrachmaCoreTests",
            dependencies: ["DrachmaCore"],
            path: "DrachmaCore/Tests"
        ),
        .executableTarget(
            name: "DrachmaMCP",
            dependencies: ["DrachmaCore"],
            path: "mcp/Sources"
        ),
    ]
)
