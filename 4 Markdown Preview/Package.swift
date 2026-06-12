// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MarkdownPreviewModule",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MarkdownPreviewModule", targets: ["MarkdownPreviewModule"])
    ],
    dependencies: [
        .package(name: "FoundationModule", path: "../2 Foundation"),
        .package(name: "ResourcesModule", path: "../9 Resources"),
        .package(name: "SputnikShared", path: "../SputnikShared"),
    ],
    targets: [
        .target(
            name: "MarkdownPreviewModule",
            dependencies: ["FoundationModule", "ResourcesModule", "SputnikShared"],
            path: ".",
            exclude: ["Tests"]
        ),
        .testTarget(
            name: "MarkdownPreviewModuleTests",
            dependencies: ["MarkdownPreviewModule"],
            path: "Tests"
        )
    ]
)
