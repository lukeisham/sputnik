// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TextEditorModule",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TextEditorModule", targets: ["TextEditorModule"])
    ],
    dependencies: [
        .package(name: "FoundationModule", path: "../2 Foundation"),
        .package(name: "ResourcesModule", path: "../9 Resources"),
    ],
    targets: [
        .target(
            name: "TextEditorModule",
            dependencies: ["FoundationModule", "ResourcesModule"],
            path: "."
        )
    ]
)
