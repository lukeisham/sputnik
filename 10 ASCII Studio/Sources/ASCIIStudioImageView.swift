import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ASCIIStudioImageView: View {
    @Bindable var model: ASCIIStudioModel
    @ObservedObject var imageEditor: ASCIIImageEditor

    // Fixed-width export presets; only used by saveAtPreset(_:)
    enum OutputPreset: String, CaseIterable {
        case small = "Small (32 cols)"
        case standard = "Standard (72 cols)"
        case large = "Large (120 cols)"

        var columns: Int {
            switch self {
            case .small: return 32
            case .standard: return 72
            case .large: return 120
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            actionBar
            Divider()
            alwaysVisibleControls
            adjustmentsDisclosure
            Divider()
            if model.showEditTools {
                editToolbar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
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

            Menu("Export Preset…") {
                ForEach(OutputPreset.allCases, id: \.self) { preset in
                    Button(preset.rawValue) { saveAtPreset(preset) }
                }
            }
            .disabled(imageEditor.grid.isEmpty)
            .help("Re-convert at a fixed column width and save, without changing the live canvas")

            Button("Copy") { copyToClipboard() }
                .disabled(imageEditor.grid.isEmpty)
                .help("Copy ASCII art to clipboard")

            Button("Insert at Cursor") {
                insertASCII(imageEditor.asString())
            }
            .disabled(imageEditor.grid.isEmpty || !model.hasKnownEditor)
            .buttonStyle(.borderedProminent)
            .help(model.hasKnownEditor ? "Insert at cursor in the editor" : "Focus the editor first")
        }
    }

    // MARK: - Always-visible controls

    private var alwaysVisibleControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Width:")
                Slider(value: $model.targetWidth, in: 20...200, step: 1)
                    .onChange(of: model.targetWidth) { _, _ in regenerateOnChange() }
                Text("\(Int(model.targetWidth)) cols")
                    .monospacedDigit()
                    .frame(width: 56, alignment: .trailing)
            }

            HStack {
                Picker("Mode:", selection: $model.conversionMode) {
                    ForEach(ImageToASCIIConverter.Mode.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .frame(width: 130)
                .onChange(of: model.conversionMode) { _, _ in regenerateOnChange() }

                Spacer()

                Toggle("Invert", isOn: $model.invert)
                    .onChange(of: model.invert) { _, _ in regenerateOnChange() }

                Spacer()

                Picker("Style:", selection: $model.rampStyle) {
                    ForEach(ImageToASCIIConverter.RampStyle.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .frame(width: 100)
                .onChange(of: model.rampStyle) { _, _ in regenerateOnChange() }
            }

            if model.rampStyle == .custom {
                TextField("Custom ramp (darkest → lightest)…", text: $model.customRampString)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: model.customRampString) { _, _ in regenerateOnChange() }
            }

            RampSwatchView(characters: effectiveRamp)

            if model.conversionMode == .lineArt {
                Picker("Edge:", selection: $model.edgeStyle) {
                    ForEach(ASCIIEdgeDetector.EdgeStyle.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .frame(width: 120)
                .onChange(of: model.edgeStyle) { _, _ in regenerateOnChange() }
            }
        }
    }

    // MARK: - Adjustments disclosure

    private var adjustmentsDisclosure: some View {
        DisclosureGroup(
            isExpanded: $model.adjustmentsExpanded,
            content: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Brightness:")
                            .frame(width: 96, alignment: .leading)
                        Slider(value: $model.brightness, in: -1.0...1.0, step: 0.05)
                            .onChange(of: model.brightness) { _, _ in regenerateOnChange() }
                        Text(String(format: "%+.2f", model.brightness))
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }

                    HStack {
                        Text("Contrast:")
                            .frame(width: 96, alignment: .leading)
                        Slider(value: $model.contrast, in: 0.0...3.0, step: 0.05)
                            .onChange(of: model.contrast) { _, _ in regenerateOnChange() }
                        Text(String(format: "%.2f", model.contrast))
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }

                    HStack {
                        Text("Light threshold:")
                            .frame(width: 96, alignment: .leading)
                        Slider(value: $model.lightThreshold, in: 0.5...1.0, step: 0.01)
                            .onChange(of: model.lightThreshold) { _, _ in regenerateOnChange() }
                        Text(String(format: "%.2f", model.lightThreshold))
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                    .help("Higher values preserve more light areas; lower values carve out more negative space")

                    Picker("Dither:", selection: $model.ditherMode) {
                        ForEach(ImageToASCIIConverter.DitherMode.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .onChange(of: model.ditherMode) { _, _ in regenerateOnChange() }
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
            Button("Select") {}
                .buttonStyle(.bordered)
                .controlSize(.small)

            Divider()

            HStack(spacing: 2) {
                TextField("Char", text: $model.replaceChar)
                    .frame(width: 36)
                    .controlSize(.small)
                Button("Replace") {
                    guard let char = model.replaceChar.first else { return }
                    imageEditor.replaceSelection(with: char)
                    model.replaceChar = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(imageEditor.selection.isEmpty)
            }

            Divider()

            Menu("Align") {
                ForEach(ASCIIImageEditor.Alignment.allCases, id: \.rawValue) { align in
                    Button(align.rawValue) {
                        imageEditor.align(align)
                    }
                }
            }
            .controlSize(.small)

            HStack(spacing: 2) {
                TextField("Fill", text: $model.fillChar)
                    .frame(width: 36)
                    .controlSize(.small)
                Button("Fill non-space") {
                    guard let char = model.fillChar.first else { return }
                    imageEditor.fill(char)
                    model.fillChar = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Replace every non-space character in the grid with the given character")

                Button("Fill all") {
                    guard let char = model.fillChar.first else { return }
                    imageEditor.fillAll(char)
                    model.fillChar = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Replace every character in the grid (including spaces) with the given character")
            }

            Spacer()

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
            Toggle(isOn: $model.showEditTools) {
                Text(model.showEditTools ? "Editing enabled" : "Editing disabled")
                    .font(.caption)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .trailing)

            ScrollView([.horizontal, .vertical]) {
                if model.isConverting {
                    ProgressView("Converting…").padding(40)
                } else if imageEditor.grid.isEmpty {
                    Text("Import an image or open a .txt file to begin.")
                        .foregroundStyle(.secondary)
                        .padding(40)
                } else {
                    if model.showEditTools {
                        editableCanvas
                    } else {
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
        VStack(spacing: 4) {
            MonoGridView(editor: imageEditor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 6) {
                Text("Insert character:")
                    .font(.caption)
                TextField("Char", text: $model.insertChar)
                    .frame(width: 36)
                    .onChange(of: model.insertChar) { _, newVal in
                        if newVal.count > 1 { model.insertChar = String(newVal.suffix(1)) }
                    }
                Button("Apply") {
                    guard let char = model.insertChar.first else { return }
                    imageEditor.replaceSelectedCell(with: char)
                }
                .disabled(imageEditor.selectedCell == nil)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Computed helpers

    private var effectiveRamp: [String] {
        if model.rampStyle == .custom {
            let chars = Array(model.customRampString)
            let source = chars.isEmpty ? ImageToASCIIConverter.RampStyle.ascii.characters : chars
            return source.map { String($0) }
        }
        return model.rampStyle.characters.map { String($0) }
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
        model.selectedImage = image
        model.sourceImageName = url.deletingPathExtension().lastPathComponent
        regenerate()
    }

    private func openTXT() {
        guard let result = ASCIIExporter.open() else { return }
        let maxLineWidth = result.content.components(separatedBy: .newlines).map(\.count).max() ?? 80
        imageEditor.load(result.content, targetColumns: maxLineWidth)
        model.targetWidth = Double(maxLineWidth)
        model.sourceImageName = result.filename
        model.showEditTools = true
    }

    private func saveToTXT() {
        let content = imageEditor.asString()
        let name = model.sourceImageName.isEmpty ? "ascii-art" : model.sourceImageName
        ASCIIExporter.save(content: content, suggestedFilename: name)
    }

    private func saveAtPreset(_ preset: OutputPreset) {
        guard let image = model.selectedImage else {
            model.showNoImageAlert = true
            return
        }

        let localSettings = ImageToASCIIConverter.Settings(
            width: preset.columns,
            invert: model.invert,
            style: model.rampStyle,
            mode: model.conversionMode,
            brightness: model.brightness,
            contrast: model.contrast,
            ditherMode: model.ditherMode,
            edgeStyle: model.edgeStyle,
            customRampString: model.customRampString,
            lightThreshold: model.lightThreshold
        )

        Task(priority: .userInitiated) {
            let result = ImageToASCIIConverter.convert(image, settings: localSettings)
            await MainActor.run {
                let baseName = model.sourceImageName.isEmpty ? "ascii-art" : model.sourceImageName
                let suffix = "_\(preset.columns)col"
                ASCIIExporter.save(content: result, suggestedFilename: baseName + suffix)
            }
        }
    }

    private func regenerateOnChange() {
        guard imageEditor.hasManualEdits else {
            regenerate()
            return
        }
        model.showDiscardWarning = true
        model.pendingAction = { [self] in regenerate() }
    }

    private func checkBeforeAction(_ action: @escaping () -> Void) {
        guard imageEditor.hasManualEdits else {
            action()
            return
        }
        model.showDiscardWarning = true
        model.pendingAction = action
    }

    private func regenerate() {
        guard let image = model.selectedImage else { return }

        model.isConverting = true
        let settings = ImageToASCIIConverter.Settings(
            width: Int(model.targetWidth),
            invert: model.invert,
            style: model.rampStyle,
            mode: model.conversionMode,
            brightness: model.brightness,
            contrast: model.contrast,
            ditherMode: model.ditherMode,
            edgeStyle: model.edgeStyle,
            customRampString: model.customRampString,
            lightThreshold: model.lightThreshold
        )

        Task(priority: .userInitiated) {
            let result = ImageToASCIIConverter.convert(image, settings: settings)
            await MainActor.run {
                imageEditor.load(result, targetColumns: Int(model.targetWidth))
                model.asciiPreview = result
                model.isConverting = false
            }
        }
    }

    private func insertASCII(_ text: String) {
        guard !text.isEmpty else { return }
        guard let textView = ASCIIStudioCoordinator.activeTextView() else { return }
        ASCIIStudioCoordinator.insertAtCursor(text, into: textView)
    }

    private func copyToClipboard() {
        let text = imageEditor.asString()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
