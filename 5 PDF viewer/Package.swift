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
        .package(name: "ResourcesModule", path: "../9 Resources")
    ],
    targets: [
        .target(
            name: "PDFViewerModule",
            dependencies: ["FoundationModule", "ResourcesModule"],
            path: "."
        )
    ]
)
