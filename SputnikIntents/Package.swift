// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SputnikIntents",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SputnikIntents", targets: ["SputnikIntents"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SputnikIntents",
            dependencies: [],
            path: "."
        )
    ]
)
