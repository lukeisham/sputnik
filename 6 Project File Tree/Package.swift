// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FileTreeModule",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FileTreeModule", targets: ["FileTreeModule"])
    ],
    dependencies: [
        .package(name: "FoundationModule", path: "../2 Foundation"),
        .package(name: "SputnikShared", path: "../SputnikShared"),
    ],
    targets: [
        .target(
            name: "FileTreeModule",
            dependencies: ["FoundationModule", "SputnikShared"],
            path: ".",
            exclude: ["Tests"]
        ),
        .testTarget(
            name: "FileTreeModuleTests",
            dependencies: ["FileTreeModule", "FoundationModule"],
            path: "Tests"
        )
    ]
)
