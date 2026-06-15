import AppKit
import FoundationModule
import SwiftUI

/// SwiftUI container for the text editor, including mode picker toolbar, search bar, and editor view.
///
/// Respects SR-1 and SW-3: editor chrome (mode picker, search bar) is module-3-specific UI
/// and lives here, not in Foundation. The panel owns the sub-views and composes them into
/// a cohesive editor interface.
///
/// **Dynamic panels:** When `isEditable` is `false` (view-only column), the editor content
/// is still rendered but `NSTextView.isEditable` is set to `false` so the user cannot type
/// into it. The property is set synchronously in `makeNSView` (see SW-3).
public struct TextEditorPanel: View {

    @Bindable var viewModel: EditorViewModel
    var settings: SettingsStore
    var appState: AppState
    var isEditable: Bool

    public init(
        viewModel: EditorViewModel,
        settings: SettingsStore,
        appState: AppState,
        isEditable: Bool = true
    ) {
        self.viewModel = viewModel
        self.settings = settings
        self.appState = appState
        self.isEditable = isEditable
    }

    /// Save-as-PDF closure, wired to the active NSTextView for PDF generation.
    private var saveAsPDFAction: (() -> Void)? {
        guard let textView = viewModel.textView else { return nil }
        return { [weak textView] in
            guard let textView, let window = textView.window else { return }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = "document.pdf"
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else { return }
                let pdfRect = textView.bounds
                let pdfData = textView.dataWithPDF(inside: pdfRect)
                guard !pdfData.isEmpty else {
                    let alert = NSAlert()
                    alert.messageText = "PDF Generation Failed"
                    alert.informativeText = "Could not generate PDF data from the editor content."
                    alert.alertStyle = .warning
                    alert.runModal()
                    return
                }
                do {
                    try pdfData.write(to: url)
                } catch {
                    let alert = NSAlert()
                    alert.messageText = "Save as PDF Failed"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }

    /// Presents a two-button alert asking the user whether to save as plain text or
    /// rendered PDF. Called only when a preview panel is open and paired.
    private func presentSaveAsPDFFormatChoice(
        plainTextAction: (() -> Void)?,
        renderedAction: @escaping () -> Void
    ) {
        guard let window = NSApp.keyWindow else { return }
        let alert = NSAlert()
        alert.messageText = "Save as PDF"
        alert.informativeText = "Save the document as plain text or as the rendered preview?"
        alert.addButton(withTitle: "Rendered")
        alert.addButton(withTitle: "Plain Text")
        alert.alertStyle = .informational
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn {
                renderedAction()
            } else {
                plainTextAction?()
            }
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Toolbar: mode picker + overflow menu
            HStack(spacing: SputnikSpacing.sm) {
                Text("Mode:")
                    .font(.system(size: SputnikFont.caption))
                    .foregroundStyle(SputnikColor.secondaryText)

                Picker("Editor Mode", selection: $viewModel.mode) {
                    ForEach(EditorMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 250)

                Spacer()

                // Overflow menu: Save as PDF…
                // When a preview panel is paired, offer a Plain Text / Rendered choice.
                Menu {
                    Button("Save as PDF…") {
                        if let renderedAction = appState.pairedPreviewSaveAsPDFAction {
                            presentSaveAsPDFFormatChoice(
                                plainTextAction: saveAsPDFAction,
                                renderedAction: renderedAction
                            )
                        } else {
                            saveAsPDFAction?()
                        }
                    }
                    .disabled(viewModel.textView == nil)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: SputnikFont.caption))
                        .foregroundStyle(SputnikColor.secondaryText)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24, height: 24)
                .accessibilityLabel("More actions")
            }
            .padding(SputnikSpacing.sm)
            .background(SputnikColor.secondaryBackground)
            .borderTop(Color(nsColor: .separatorColor), width: 1)

            // Search bar (mounted but initially hidden)
            if let search = viewModel.searchController {
                SearchBarView(controller: search)
            }

            // Editor view
            EditorView(
                viewModel: viewModel, settings: settings, appState: appState, isEditable: isEditable
            )
        }
        .overlay(alignment: .trailing) {
            Minimap()
        }
        .onAppear {
            appState.activeWindow?.minimapTargetScrollView = viewModel.scrollView
        }
        .onDisappear {
            if appState.activeWindow?.minimapTargetScrollView === viewModel.scrollView {
                appState.activeWindow?.minimapTargetScrollView = nil
            }
        }
    }
}

// Helper view extension for border drawing.
extension View {
    fileprivate func borderTop(_ color: Color, width: CGFloat) -> some View {
        self.border(color, width: width)
    }
}
