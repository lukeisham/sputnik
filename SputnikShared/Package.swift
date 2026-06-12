// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SputnikShared",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SputnikShared", targets: ["SputnikShared"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SputnikShared",
            dependencies: [],
            path: "Sources"
        ),
    ]
)
