// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ResourcesModule",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ResourcesModule", targets: ["ResourcesModule"])
    ],
    dependencies: [
        .package(name: "FoundationModule", path: "../2 Foundation")
    ],
    targets: [
        .target(
            name: "ResourcesModule",
            dependencies: ["FoundationModule"],
            path: "."
        )
    ]
)
