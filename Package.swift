// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "drachma",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DrachmaCore", targets: ["DrachmaCore"]),
        .library(name: "DrachmaAuth", targets: ["DrachmaAuth"]),
        .library(name: "DrachmaAuthClient", targets: ["DrachmaAuthClient"]),
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
        // Used only on Linux (macOS uses the system CryptoKit); see PKCE.swift.
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"5.0.0"),
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
            dependencies: [
                // Resolves `import Crypto` on Linux; inert on macOS (CryptoKit).
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            path: "Sources/DrachmaAuth"
        ),
        .testTarget(
            name: "DrachmaAuthTests",
            dependencies: ["DrachmaAuth", .product(name: "MCP", package: "swift-sdk")],
            path: "Tests/DrachmaAuthTests"
        ),
        .target(
            name: "DrachmaAuthClient",
            dependencies: ["DrachmaAuth"],
            path: "Sources/DrachmaAuthClient"
        ),
        .testTarget(
            name: "DrachmaAuthClientTests",
            dependencies: ["DrachmaAuthClient", "DrachmaAuth"],
            path: "Tests/DrachmaAuthClientTests"
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
                "DrachmaAuthClient",
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
