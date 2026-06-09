// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PDFViewerModule",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PDFViewerModule", targets: ["PDFViewerModule"])
    ],
    dependencies: [
        .package(name: "FoundationModule", path: "../2 Foundation")
    ],
    targets: [
        .target(
            name: "PDFViewerModule",
            dependencies: ["FoundationModule"],
            path: "."
        )
    ]
)
