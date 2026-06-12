// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PDFViewerModule",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PDFViewerModule", targets: ["PDFViewerModule"])
    ],
    dependencies: [
        .package(name: "FoundationModule", path: "../2 Foundation"),
        .package(name: "ResourcesModule", path: "../9 Resources"),
        .package(name: "SputnikShared", path: "../SputnikShared"),
    ],
    targets: [
        .target(
            name: "PDFViewerModule",
            dependencies: ["FoundationModule", "ResourcesModule", "SputnikShared"],
            path: ".",
            exclude: [
                ".build",
                ".swiftpm",
                "Package.swift",
                "Tests",
                // Stale build artifacts from a prior build
                "ASCIIArtHelpContent-2.d",
                "ASCIIArtHelpContent-2.dia",
                "ASCIIArtHelpContent-2.swiftdeps",
                "ASCIIArtHelpContent-2.swiftmodule",
                "ASCIIArtHelpCoordinator-2.d",
                "ASCIIArtHelpCoordinator-2.dia",
                "ASCIIArtHelpCoordinator-2.swiftdeps",
                "ASCIIArtHelpCoordinator-2.swiftmodule",
                "ASCIIArtHelpIndex-2.d",
                "ASCIIArtHelpIndex-2.dia",
                "ASCIIArtHelpIndex-2.swiftdeps",
                "ASCIIArtHelpIndex-2.swiftmodule",
                "ASCIIArtHelpPanelView-2.d",
                "ASCIIArtHelpPanelView-2.dia",
                "ASCIIArtHelpPanelView-2.swiftdeps",
                "ASCIIArtHelpPanelView-2.swiftmodule",
                "MarkdownHelpContent-2.d",
                "MarkdownHelpContent-2.dia",
                "MarkdownHelpContent-2.swiftdeps",
                "MarkdownHelpContent-2.swiftmodule",
                "MarkdownHelpCoordinator-2.d",
                "MarkdownHelpCoordinator-2.dia",
                "MarkdownHelpCoordinator-2.swiftdeps",
                "MarkdownHelpCoordinator-2.swiftmodule",
            ]
        ),
        .testTarget(
            name: "PDFViewerModuleTests",
            dependencies: ["PDFViewerModule"],
            path: "Tests"
        )
    ]
)
