// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FoundationModule",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FoundationModule", targets: ["FoundationModule"]),
        .library(name: "TestingSupport", targets: ["TestingSupport"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "FoundationModule",
            dependencies: [],
            path: ".",
            exclude: ["Tests", "2.7 Utilities/TestingSupport.swift"],
            sources: [
                "2.0 App Overview",
                "2.1 Inter-Panel communication",
                "2.2 Global State Management",
                "2.3 Settings",
                "2.4 UI and UX",
                "2.5 Persistence",
                "2.6 App Lifecycle",
                "2.7 Utilities",
                "2.8 Apple Intent",
                "2.9 Shared",
            ]
        ),
        .target(
            name: "TestingSupport",
            dependencies: ["FoundationModule"],
            path: "2.7 Utilities",
            exclude: [
                "ClosureMenuItem.swift",
                "CompletionProviding.swift",
                "HelpContextResolving.swift",
                "KeychainService.swift",
                "MainAIMonitor.swift",
                "MoreContextMenu.swift",
                "ProcessMonitor.swift",
                "SlashCommand.swift",
                "SlashCommandRegistry.swift",
                "SupportingAIMonitor.swift",
            ],
            sources: ["TestingSupport.swift"]
        ),
        .testTarget(
            name: "FoundationModuleTests",
            dependencies: ["FoundationModule", "TestingSupport"],
            path: "Tests"
        ),
    ]
)
