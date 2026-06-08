// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NetworkingSputnik",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "NetworkingSputnik", targets: ["NetworkingSputnik"])
    ],
    targets: [
        .target(
            name: "NetworkingSputnik",
            path: "Sources"
        ),
        .testTarget(
            name: "NetworkingSputnikTests",
            dependencies: ["NetworkingSputnik"],
            path: "Tests"
        )
    ]
)
