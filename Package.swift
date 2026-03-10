// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeUsageCore",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "ClaudeUsageCore",
            targets: ["ClaudeUsageCore"]
        )
    ],
    targets: [
        .target(
            name: "ClaudeUsageCore",
            path: "Sources/ClaudeUsageCore"
        ),
        .testTarget(
            name: "ClaudeUsageCoreTests",
            dependencies: ["ClaudeUsageCore"],
            path: "Tests/ClaudeUsageCoreTests"
        )
    ]
)
