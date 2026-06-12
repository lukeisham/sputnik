// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TerminalModule",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TerminalModule", targets: ["TerminalModule"])
    ],
    dependencies: [
        .package(name: "FoundationModule", path: "../2 Foundation"),
        .package(name: "SputnikShared", path: "../SputnikShared"),
    ],
    targets: [
        .target(
            name: "TerminalModule",
            dependencies: ["FoundationModule", "SputnikShared"],
            path: ".",
            exclude: ["Tests"]
        ),
        .testTarget(
            name: "TerminalModuleTests",
            dependencies: ["TerminalModule"],
            path: "Tests"
        )
    ]
)
