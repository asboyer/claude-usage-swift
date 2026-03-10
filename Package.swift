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
            path: "src",
            sources: ["UsageCore.swift"]
        ),
        .testTarget(
            name: "ClaudeUsageCoreTests",
            dependencies: ["ClaudeUsageCore"],
            path: "tests/ClaudeUsageCoreTests"
        )
    ]
)
