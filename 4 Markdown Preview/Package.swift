// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MarkdownPreviewModule",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MarkdownPreviewModule", targets: ["MarkdownPreviewModule"])
    ],
    dependencies: [
        .package(name: "FoundationModule", path: "../2 Foundation")
    ],
    targets: [
        .target(
            name: "MarkdownPreviewModule",
            dependencies: ["FoundationModule"],
            path: "."
        )
    ]
)
