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
            exclude: ["Package.swift", ".build", ".swiftpm", "Tests"],
            resources: [
                .process("9.1 ASCII Library"),
                .process("9.2 ASCII art Help"),
                .process("9.3 Markdown Help"),
                .process("9.4 Html Help"),
                .process("9.5 Grammar Help"),
            ]
        ),
        .testTarget(
            name: "ResourcesModuleTests",
            dependencies: ["ResourcesModule"],
            path: "Tests"
        ),
    ]
)
