import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// SwiftUI two-tab content for the ASCII Studio panel.
///
/// Tab 1 (Image → ASCII): live preview, width/invert/style controls, insert at cursor.
/// Tab 2 (Library): browse bundled clips by category, insert at cursor.
///
/// All `NSTextStorage` writes are performed on `@MainActor` via `ASCIILibraryBrowser`
/// and the local `insertASCII` helper.
public struct ASCIIStudioView: View {

    // MARK: - State

    @State private var selectedTab: Tab = .imageToASCII
    @State private var selectedImage: NSImage? = nil
    @State private var asciiPreview: String = ""
    @State private var targetWidth: Double = 80
    @State private var invert: Bool = false
    @State private var rampStyle: ImageToASCIIConverter.RampStyle = .block
    @State private var selectedCategory: ASCIILibraryBrowser.Category = .frames
    @State private var isConverting: Bool = false

    private let textView: NSTextView
    private let library = ASCIILibraryBrowser()

    public enum Tab: String, CaseIterable {
        case imageToASCII = "Image → ASCII"
        case library = "Library"
    }

    public init(textView: NSTextView) {
        self.textView = textView
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            Group {
                switch selectedTab {
                case .imageToASCII: imageTab
                case .library: libraryTab
                }
            }
        }
        .frame(minWidth: 480, minHeight: 500)
    }

    // MARK: - Image → ASCII tab

    private var imageTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button("Import PNG / JPEG / TIFF…") { importImage() }

            HStack {
                Text("Width:")
                Slider(value: $targetWidth, in: 20...200, step: 1)
                    .onChange(of: targetWidth) { _, _ in regenerate() }
                Text("\(Int(targetWidth)) cols")
                    .monospacedDigit()
                    .frame(width: 64, alignment: .trailing)
            }

            HStack {
                Toggle("Invert", isOn: $invert)
                    .onChange(of: invert) { _, _ in regenerate() }
                Spacer()
                Picker("Style:", selection: $rampStyle) {
                    ForEach(ImageToASCIIConverter.RampStyle.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .frame(width: 180)
                .onChange(of: rampStyle) { _, _ in regenerate() }
            }

            ScrollView([.horizontal, .vertical]) {
                if isConverting {
                    ProgressView("Converting…").padding(40)
                } else if asciiPreview.isEmpty {
                    Text("Import an image to see the ASCII preview.")
                        .foregroundStyle(.secondary)
                        .padding(40)
                } else {
                    Text(asciiPreview)
                        .font(.system(size: 9, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .frame(minHeight: 200)

            HStack {
                Spacer()
                Button("Insert at Cursor") { insertASCII(asciiPreview) }
                    .disabled(asciiPreview.isEmpty)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    // MARK: - Library tab

    private var libraryTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Category:", selection: $selectedCategory) {
                ForEach(ASCIILibraryBrowser.Category.allCases, id: \.self) {
                    Text($0.rawValue).tag($0)
                }
            }
            .pickerStyle(.segmented)

            let clips = library.clips(for: selectedCategory)
            if clips.isEmpty {
                VStack {
                    Spacer()
                    Text("No clips available for \(selectedCategory.rawValue).")
                        .foregroundStyle(.secondary)
                    Text("Add .txt files to Resources/ASCIILibrary/\(selectedCategory.rawValue)/")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 200))],
                        spacing: 8
                    ) {
                        ForEach(clips) { clip in clipCard(clip) }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding()
    }

    private func clipCard(_ clip: ASCIILibraryBrowser.Clip) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(clip.name)
                .font(.caption.bold())
                .lineLimit(1)
            Text(clip.content)
                .font(.system(size: 9, design: .monospaced))
                .lineLimit(8)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Insert") { library.insert(clip, into: textView) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Helpers

    private func importImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK,
            let url = panel.url,
            let image = NSImage(contentsOf: url)
        else { return }
        selectedImage = image
        regenerate()
    }

    private func regenerate() {
        guard let image = selectedImage else { return }
        isConverting = true
        let w = Int(targetWidth)
        let inv = invert
        let style = rampStyle
        Task(priority: .userInitiated) {
            let result = ImageToASCIIConverter.convert(image, width: w, invert: inv, style: style)
            await MainActor.run {
                asciiPreview = result
                isConverting = false
            }
        }
    }

    private func insertASCII(_ text: String) {
        guard !text.isEmpty, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        storage.replaceCharacters(in: range, with: text)
    }
}
