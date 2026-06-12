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

    public var body: some View {
        VStack(spacing: 0) {
            // Toolbar: mode picker
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
    }
}

// Helper view extension for border drawing.
extension View {
    fileprivate func borderTop(_ color: Color, width: CGFloat) -> some View {
        self.border(color, width: width)
    }
}
