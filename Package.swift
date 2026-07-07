// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "drachma",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DrachmaCore", targets: ["DrachmaCore"]),
        .library(name: "DrachmaAuth", targets: ["DrachmaAuth"]),
        .library(name: "DrachmaServer", targets: ["DrachmaServer"]),
        .library(name: "DrachmaApp", targets: ["DrachmaApp"]),
        .executable(name: "drachma-mcp", targets: ["DrachmaMCP"]),
        .executable(name: "drachma-server", targets: ["drachma-server"]),
        .executable(name: "render-screenshots", targets: ["RenderScreenshots"]),
        .executable(name: "render-icon", targets: ["RenderIcon"]),
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.25.0"),
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
        .target(
            name: "DrachmaApp",
            dependencies: ["DrachmaCore"],
            path: "ios/Drachma",
            exclude: ["README.md"]
        ),
        .testTarget(
            name: "DrachmaAppTests",
            dependencies: ["DrachmaApp", "DrachmaCore"],
            path: "ios/DrachmaTests"
        ),
        .executableTarget(
            name: "RenderScreenshots",
            dependencies: ["DrachmaApp", "DrachmaCore"],
            path: "tools/RenderScreenshots"
        ),
        .executableTarget(
            name: "RenderIcon",
            path: "tools/RenderIcon"
        ),
        .target(
            name: "DrachmaAuth",
            path: "Sources/DrachmaAuth"
        ),
        .testTarget(
            name: "DrachmaAuthTests",
            dependencies: ["DrachmaAuth", .product(name: "MCP", package: "swift-sdk")],
            path: "Tests/DrachmaAuthTests"
        ),
        .target(
            name: "DrachmaServer",
            dependencies: [
                "DrachmaCore",
                "DrachmaAuth",
                .product(name: "Hummingbird", package: "hummingbird"),
            ],
            path: "Sources/DrachmaServer"
        ),
        .testTarget(
            name: "DrachmaServerTests",
            dependencies: [
                "DrachmaServer",
                "DrachmaAuth",
                "DrachmaCore",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdTesting", package: "hummingbird"),
            ],
            path: "Tests/DrachmaServerTests"
        ),
        .executableTarget(
            name: "drachma-server",
            dependencies: [
                "DrachmaServer",
                "DrachmaCore",
                "DrachmaAuth",
                .product(name: "Hummingbird", package: "hummingbird"),
            ],
            path: "Sources/drachma-server"
        ),
        .executableTarget(
            name: "DrachmaMCP",
            dependencies: [
                "DrachmaCore",
                .product(name: "MCP", package: "swift-sdk"),
            ],
            path: "mcp/Sources"
        ),
    ]
)
