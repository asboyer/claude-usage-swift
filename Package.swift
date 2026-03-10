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
            exclude: [
                "main.swift",
                "AppConstants.swift",
                "ClaudeUsage.swift",
                "AppDelegate+MenuAndRefresh.swift",
                "TimeFormatting.swift",
                "SoundPlayback.swift",
                "api",
                "graph",
                "history"
            ],
            sources: ["UsageCore.swift"]
        ),
        .testTarget(
            name: "ClaudeUsageCoreTests",
            dependencies: ["ClaudeUsageCore"],
            path: "tests/ClaudeUsageCoreTests"
        )
    ]
)
