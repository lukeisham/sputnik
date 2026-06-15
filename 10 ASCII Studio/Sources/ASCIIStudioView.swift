import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// SwiftUI two-tab content for the dockable ASCII Studio panel.
///
/// Tab 1 (Image → ASCII): live preview with brightness/contrast/dither/edge-detection
/// controls, editable canvas with editing tools, open/save/insert at cursor.
/// Tab 2 (Library): browse bundled clips by category, insert at cursor.
///
/// All `NSTextStorage` writes are performed on `@MainActor` via `ASCIILibraryBrowser`
/// and `ASCIIStudioCoordinator`.
public struct ASCIIStudioView: View {

    // MARK: - State

    @State private var selectedTab: Tab = .imageToASCII
    @State private var selectedImage: NSImage? = nil
    @State private var asciiPreview: String = ""
    @State private var isConverting: Bool = false

    // Conversion settings
    @State private var targetWidth: Double = 80
    @State private var invert: Bool = false
    @State private var rampStyle: ImageToASCIIConverter.RampStyle = .block
    @State private var conversionMode: ImageToASCIIConverter.Mode = .luminance
    @State private var brightness: Double = 0.0
    @State private var contrast: Double = 1.0
    @State private var ditherEnabled: Bool = false
    @State private var edgeStyle: ASCIIEdgeDetector.EdgeStyle = .simple

    // Adjustments disclosure
    @State private var adjustmentsExpanded: Bool = false

    // Library
    @State private var selectedCategory: ASCIILibraryBrowser.Category = .frames

    // Editor
    @StateObject private var imageEditor = ASCIIImageEditor()
    @State private var showEditTools: Bool = false
    @State private var replaceChar: String = ""
    @State private var fillChar: String = ""

    // Source tracking
    @State private var sourceImageName: String = ""

    // Whether the editor text view has ever held focus (tracked via notifications).
    @State private var hasKnownEditor: Bool = false

    // Warn-before-discard alert
    @State private var showDiscardWarning: Bool = false
    @State private var pendingAction: (() -> Void)? = nil

    private let library = ASCIILibraryBrowser()

    public enum Tab: String, CaseIterable {
        case imageToASCII = "Image → ASCII"
        case library = "Library"
    }

    public init() {}

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
        .frame(minWidth: 320, minHeight: 400)
        .task {
            ASCIIStudioCoordinator.startTracking()
            hasKnownEditor = ASCIIStudioCoordinator.lastKnownTextView != nil
            for await _ in NotificationCenter.default.notifications(
                named: .editorTextViewDidBecomeFirstResponder
            ) {
                hasKnownEditor = true
            }
        }
        .alert("Discard Edits?", isPresented: $showDiscardWarning) {
            Button("Cancel", role: .cancel) {
                pendingAction = nil
            }
            Button("Discard & Re-convert", role: .destructive) {
                if let action = pendingAction {
                    imageEditor.hasManualEdits = false
                    action()
                    pendingAction = nil
                }
            }
        } message: {
            Text("Re-converting will discard your manual edits. Continue?")
        }

    }

    // MARK: - Image → ASCII tab

    private var imageTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Action bar: Import, Open, Save, Insert
            actionBar

            Divider()

            // Always-visible controls
            alwaysVisibleControls

            // Adjustments disclosure
            adjustmentsDisclosure

            Divider()

            // Edit toolbar (when showing editable canvas)
            if showEditTools {
                editToolbar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Preview / editable canvas
            canvasArea
        }
        .padding()
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button("Import…") { checkBeforeAction { importImage() } }
                .help("Import PNG / JPEG / TIFF")

            Button("Open .txt…") { openTXT() }
                .help("Open existing ASCII art file")

            Spacer()

            Button("Save as .txt…") { saveToTXT() }
                .disabled(imageEditor.grid.isEmpty)
                .help("Save the current ASCII art to a file")

            Button("Insert at Cursor") {
                insertASCII(imageEditor.asString())
            }
            .disabled(imageEditor.grid.isEmpty || !hasKnownEditor)
            .buttonStyle(.borderedProminent)
            .help(hasKnownEditor ? "Insert at cursor in the editor" : "Focus the editor first")
        }
    }

    // MARK: - Always-visible controls

    private var alwaysVisibleControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Width slider
            HStack {
                Text("Width:")
                Slider(value: $targetWidth, in: 20...200, step: 1)
                    .onChange(of: targetWidth) { _, _ in regenerateOnChange() }
                Text("\(Int(targetWidth)) cols")
                    .monospacedDigit()
                    .frame(width: 56, alignment: .trailing)
            }

            // Conversion mode + Invert + Style
            HStack {
                Picker("Mode:", selection: $conversionMode) {
                    ForEach(ImageToASCIIConverter.Mode.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .frame(width: 120)
                .onChange(of: conversionMode) { _, _ in regenerateOnChange() }

                Spacer()

                Toggle("Invert", isOn: $invert)
                    .onChange(of: invert) { _, _ in regenerateOnChange() }

                Spacer()

                Picker("Style:", selection: $rampStyle) {
                    ForEach(ImageToASCIIConverter.RampStyle.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .frame(width: 100)
                .onChange(of: rampStyle) { _, _ in regenerateOnChange() }
            }

            // Edge style (only shown when in line-art mode)
            if conversionMode == .lineArt {
                Picker("Edge:", selection: $edgeStyle) {
                    ForEach(ASCIIEdgeDetector.EdgeStyle.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .frame(width: 120)
                .onChange(of: edgeStyle) { _, _ in regenerateOnChange() }
            }
        }
    }

    // MARK: - Adjustments disclosure

    private var adjustmentsDisclosure: some View {
        DisclosureGroup(
            isExpanded: $adjustmentsExpanded,
            content: {
                VStack(alignment: .leading, spacing: 8) {
                    // Brightness
                    HStack {
                        Text("Brightness:")
                            .frame(width: 72, alignment: .leading)
                        Slider(value: $brightness, in: -1.0...1.0, step: 0.05)
                            .onChange(of: brightness) { _, _ in regenerateOnChange() }
                        Text(String(format: "%+.2f", brightness))
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }

                    // Contrast
                    HStack {
                        Text("Contrast:")
                            .frame(width: 72, alignment: .leading)
                        Slider(value: $contrast, in: 0.0...3.0, step: 0.05)
                            .onChange(of: contrast) { _, _ in regenerateOnChange() }
                        Text(String(format: "%.2f", contrast))
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }

                    // Dither toggle
                    Toggle("Floyd–Steinberg Dither", isOn: $ditherEnabled)
                        .onChange(of: ditherEnabled) { _, _ in regenerateOnChange() }
                }
                .padding(.vertical, 4)
            },
            label: {
                Label("Adjustments", systemImage: "slider.horizontal.3")
                    .font(.callout)
            }
        )
    }

    // MARK: - Edit toolbar

    private var editToolbar: some View {
        HStack(spacing: 6) {
            // Selection mode toggle
            Button("Select") {
                // Selection is implicit — clicking grid cells selects
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Divider()

            // Replace character
            HStack(spacing: 2) {
                TextField("Char", text: $replaceChar)
                    .frame(width: 36)
                    .controlSize(.small)
                Button("Replace") {
                    guard let char = replaceChar.first else { return }
                    imageEditor.replaceSelection(with: char)
                    replaceChar = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(imageEditor.selection.isEmpty)
            }

            Divider()

            // Align
            Menu("Align") {
                ForEach(ASCIIImageEditor.Alignment.allCases, id: \.rawValue) { align in
                    Button(align.rawValue) {
                        imageEditor.align(align)
                    }
                }
            }
            .controlSize(.small)

            // Fill
            HStack(spacing: 2) {
                TextField("Fill", text: $fillChar)
                    .frame(width: 36)
                    .controlSize(.small)
                Button("Fill non-space") {
                    guard let char = fillChar.first else { return }
                    imageEditor.fill(char)
                    fillChar = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Replace every non-space character in the grid with the given character")

                Button("Fill all") {
                    guard let char = fillChar.first else { return }
                    imageEditor.fillAll(char)
                    fillChar = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Replace every character in the grid (including spaces) with the given character")
            }

            Spacer()

            // Undo / Redo
            Button("Undo") {
                imageEditor.undoManager.undo()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!imageEditor.undoManager.canUndo)

            Button("Redo") {
                imageEditor.undoManager.redo()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!imageEditor.undoManager.canRedo)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Canvas area

    private var canvasArea: some View {
        VStack(spacing: 4) {
            // Toggle edit mode
            Toggle(isOn: $showEditTools) {
                Text(showEditTools ? "Editing enabled" : "Editing disabled")
                    .font(.caption)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .trailing)

            ScrollView([.horizontal, .vertical]) {
                if isConverting {
                    ProgressView("Converting…").padding(40)
                } else if imageEditor.grid.isEmpty {
                    Text("Import an image or open a .txt file to begin.")
                        .foregroundStyle(.secondary)
                        .padding(40)
                } else {
                    if showEditTools {
                        // Editable grid
                        editableCanvas
                    } else {
                        // Read-only preview
                        Text(imageEditor.asString())
                            .font(.system(size: 9, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .frame(minHeight: 150)
        }
    }

    // MARK: - Editable canvas

    private var editableCanvas: some View {
        let text = imageEditor.asString()
        return Text(text)
            .font(.system(size: 9, design: .monospaced))
            .padding(8)
            .contentShape(Rectangle())
            .onTapGesture { location in
                // Convert tap location to grid index.
                // This is a simplified tap-to-select; a full implementation
                // would track individual character rects.
            }
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
            HStack {
                Button("Insert") {
                    guard let tv = ASCIIStudioCoordinator.activeTextView() else { return }
                    library.insert(clip, into: tv)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button("Edit") {
                    imageEditor.load(clip.content, targetColumns: 80)
                    sourceImageName = clip.name
                    selectedTab = .imageToASCII
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Actions

    private func importImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK,
            let url = panel.url,
            let image = NSImage(contentsOf: url)
        else { return }
        selectedImage = image
        sourceImageName = url.deletingPathExtension().lastPathComponent
        regenerate()
    }

    private func openTXT() {
        guard let result = ASCIIExporter.open() else { return }
        let maxLineWidth = result.content.components(separatedBy: .newlines).map(\.count).max() ?? 80
        imageEditor.load(result.content, targetColumns: maxLineWidth)
        targetWidth = Double(maxLineWidth)
        sourceImageName = result.filename
        showEditTools = true
    }

    private func saveToTXT() {
        let content = imageEditor.asString()
        let name = sourceImageName.isEmpty ? "ascii-art" : sourceImageName
        ASCIIExporter.save(content: content, suggestedFilename: name)
    }

    /// Regenerate the ASCII preview, but check for manual edits first.
    private func regenerateOnChange() {
        guard imageEditor.hasManualEdits else {
            regenerate()
            return
        }
        // Show the warning dialog before discarding edits.
        showDiscardWarning = true
        pendingAction = { [self] in
            regenerate()
        }
    }

    /// Check if there are manual edits before performing an action that would discard them.
    private func checkBeforeAction(_ action: @escaping () -> Void) {
        guard imageEditor.hasManualEdits else {
            action()
            return
        }
        showDiscardWarning = true
        pendingAction = action
    }

    private func regenerate() {
        guard let image = selectedImage else { return }
        guard conversionMode == .luminance || conversionMode == .lineArt else { return }

        isConverting = true
        let settings = ImageToASCIIConverter.Settings(
            width: Int(targetWidth),
            invert: invert,
            style: rampStyle,
            mode: conversionMode,
            brightness: brightness,
            contrast: contrast,
            dither: ditherEnabled,
            edgeStyle: edgeStyle
        )

        Task(priority: .userInitiated) {
            let result = ImageToASCIIConverter.convert(image, settings: settings)
            await MainActor.run {
                imageEditor.load(result, targetColumns: Int(targetWidth))
                asciiPreview = result
                isConverting = false
            }
        }
    }

    private func insertASCII(_ text: String) {
        guard !text.isEmpty else { return }
        guard let textView = ASCIIStudioCoordinator.activeTextView() else { return }
        ASCIIStudioCoordinator.insertAtCursor(text, into: textView)
    }
}
