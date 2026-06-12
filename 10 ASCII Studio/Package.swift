// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ASCIIStudioModule",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ASCIIStudioModule", targets: ["ASCIIStudioModule"])
    ],
    dependencies: [
        .package(name: "FoundationModule", path: "../2 Foundation"),
        .package(name: "ResourcesModule", path: "../9 Resources"),
    ],
    targets: [
        .target(
            name: "ASCIIStudioModule",
            dependencies: ["FoundationModule", "ResourcesModule"],
            path: ".",
            exclude: ["Tests"]
        ),
        .testTarget(
            name: "ASCIIStudioModuleTests",
            dependencies: ["ASCIIStudioModule"],
            path: "Tests"
        ),
    ]
)
