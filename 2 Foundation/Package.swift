// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FoundationModule",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FoundationModule", targets: ["FoundationModule"]),
        .library(name: "TestingSupport", targets: ["TestingSupport"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "FoundationModule",
            dependencies: [],
            path: ".",
            exclude: ["Tests", "2.7 Utilities/TestingSupport.swift"]
        ),
        .target(
            name: "TestingSupport",
            dependencies: ["FoundationModule"],
            path: "2.7 Utilities",
            sources: ["TestingSupport.swift"]
        ),
        .testTarget(
            name: "FoundationModuleTests",
            dependencies: ["FoundationModule", "TestingSupport"],
            path: "Tests"
        ),
    ]
)
