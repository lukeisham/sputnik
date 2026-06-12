// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SputnikApp",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Modern path-based local dependencies (identity is inferred from the sub-manifest)
        .package(path: "2 Foundation"),
        .package(path: "3 Text Editor"),
        .package(path: "4 Markdown Preview"),
        .package(path: "5 PDF viewer"),
        .package(path: "6 Project File Tree"),
        .package(path: "7 Terminal"),
        .package(path: "8 HTML Preview"),
        .package(path: "9 Resources"),
        .package(path: "SputnikIntents"),
    ],
    targets: [
        .executableTarget(
            name: "SputnikApp",  // ← this becomes SputnikApp.app
            dependencies: [
                // Explicitly bind the product name to the package identity
                .product(name: "FoundationModule", package: "2 Foundation"),
                .product(name: "TextEditorModule", package: "3 Text Editor"),
                .product(name: "MarkdownPreviewModule", package: "4 Markdown Preview"),
                .product(name: "PDFViewerModule", package: "5 PDF viewer"),
                .product(name: "FileTreeModule", package: "6 Project File Tree"),
                .product(name: "TerminalModule", package: "7 Terminal"),
                .product(name: "HTMLPreviewModule", package: "8 HTML Preview"),
                .product(name: "ResourcesModule", package: "9 Resources"),
                .product(name: "SputnikIntents", package: "SputnikIntents"),
            ],
            path: "App-Sputnik",
            exclude: ["Sputnik.entitlements", "Info.plist"],
            resources: [
                .process("Assets.xcassets")
            ]
        )
    ]
)
