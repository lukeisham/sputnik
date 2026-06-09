// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SputnikApp",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "FoundationModule",      path: "2 Foundation"),
        .package(name: "TextEditorModule",      path: "3 Text Editor"),
        .package(name: "MarkdownPreviewModule", path: "4 Markdown Preview"),
        .package(name: "PDFViewerModule",       path: "5 PDF viewer"),
        .package(name: "FileTreeModule",        path: "6 Project File Tree"),
        .package(name: "TerminalModule",        path: "7 Terminal"),
        .package(name: "HTMLPreviewModule",     path: "8 HTML Preview"),
        .package(name: "ResourcesModule",       path: "9 Resources"),
    ],
    targets: [
        .executableTarget(
            name: "SputnikApp",
            dependencies: [
                "FoundationModule",
                "TextEditorModule",
                "MarkdownPreviewModule",
                "PDFViewerModule",
                "FileTreeModule",
                "TerminalModule",
                "HTMLPreviewModule",
                "ResourcesModule",
            ],
            path: "App-Sputnik",
            exclude: ["Assets.xcassets"]
        )
    ]
)
