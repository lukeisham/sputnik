// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TextEditorModule",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TextEditorModule", targets: ["TextEditorModule"])
    ],
    dependencies: [
        .package(name: "FoundationModule", path: "../2 Foundation")
    ],
    targets: [
        .target(
            name: "TextEditorModule",
            dependencies: ["FoundationModule"],
            path: "."
        )
    ]
)
