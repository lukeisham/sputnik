import SwiftUI

/// Thin coordinator for the ASCII Studio panel.
///
/// Owns the shared model and `imageEditor` lifecycle, switches between the two
/// tab views, and presents the two discard/missing-image alert dialogs.
public struct ASCIIStudioView: View {

    @State private var model = ASCIIStudioModel()
    @StateObject private var imageEditor = ASCIIImageEditor()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $model.selectedTab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            Group {
                switch model.selectedTab {
                case .imageToASCII:
                    ASCIIStudioImageView(model: model, imageEditor: imageEditor)
                case .library:
                    ASCIIStudioLibraryView(model: model, library: model.library, imageEditor: imageEditor)
                }
            }
        }
        .frame(minWidth: 320, minHeight: 400)
        .task {
            ASCIIStudioCoordinator.startTracking()
            model.hasKnownEditor = ASCIIStudioCoordinator.lastKnownTextView != nil
            for await _ in NotificationCenter.default.notifications(
                named: .editorTextViewDidBecomeFirstResponder
            ) {
                model.hasKnownEditor = true
            }
        }
        .alert("Discard Edits?", isPresented: $model.showDiscardWarning) {
            Button("Cancel", role: .cancel) {
                model.pendingAction = nil
            }
            Button("Discard & Re-convert", role: .destructive) {
                if let action = model.pendingAction {
                    imageEditor.hasManualEdits = false
                    action()
                    model.pendingAction = nil
                }
            }
        } message: {
            Text("Re-converting will discard your manual edits. Continue?")
        }
        .alert("No Source Image", isPresented: $model.showNoImageAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Import an image first to use preset export sizes.")
        }
    }
}
