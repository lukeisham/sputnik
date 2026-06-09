// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FileTreeModule",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FileTreeModule", targets: ["FileTreeModule"])
    ],
    dependencies: [
        .package(name: "FoundationModule", path: "../2 Foundation")
    ],
    targets: [
        .target(
            name: "FileTreeModule",
            dependencies: ["FoundationModule"],
            path: "."
        )
    ]
)
