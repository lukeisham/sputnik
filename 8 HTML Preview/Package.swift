// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HTMLPreviewModule",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HTMLPreviewModule", targets: ["HTMLPreviewModule"])
    ],
    dependencies: [
        .package(name: "FoundationModule", path: "../2 Foundation"),
        .package(name: "ResourcesModule", path: "../9 Resources"),
        .package(name: "SputnikShared", path: "../SputnikShared"),
    ],
    targets: [
        .target(
            name: "HTMLPreviewModule",
            dependencies: ["FoundationModule", "ResourcesModule", "SputnikShared"],
            path: ".",
            exclude: ["Tests"]
        ),
        .testTarget(
            name: "HTMLPreviewModuleTests",
            dependencies: ["HTMLPreviewModule"],
            path: "Tests"
        )
    ]
)
