// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "UIComponentsSputnik",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "UIComponentsSputnik", targets: ["UIComponentsSputnik"])
    ],
    targets: [
        .target(
            name: "UIComponentsSputnik",
            path: "Sources"
        ),
        .testTarget(
            name: "UIComponentsSputnikTests",
            dependencies: ["UIComponentsSputnik"],
            path: "Tests"
        )
    ]
)
