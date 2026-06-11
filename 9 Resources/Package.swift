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
            path: ".",
            resources: [
                // .copy preserves directory structure so subdirectory: paths work
                // without resource-name collisions (e.g. multiple index.json files).
                .copy("9.1 ASCII Library"),
            ]
        )
    ]
)
