// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FoundationModule",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FoundationModule", targets: ["FoundationModule"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "FoundationModule",
            dependencies: [],
            path: "."
        )
    ]
)
