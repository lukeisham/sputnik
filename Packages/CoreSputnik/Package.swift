// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CoreSputnik",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "CoreSputnik", targets: ["CoreSputnik"])
    ],
    targets: [
        .target(
            name: "CoreSputnik",
            path: "Sources"
        ),
        .testTarget(
            name: "CoreSputnikTests",
            dependencies: ["CoreSputnik"],
            path: "Tests"
        )
    ]
)
