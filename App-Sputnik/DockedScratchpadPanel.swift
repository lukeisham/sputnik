import FoundationModule
import SwiftUI

/// A docked scratchpad panel, anchored next to the Terminal strip.
///
/// Replaces the old floating `ScratchpadPanel` overlay. The scratchpad sits beside
/// the Terminal, resizable horizontally, and is toggled with ⇧⌘K.
///
/// **State:** `scratchpadDockedWidth` is persisted via `UserDefaults` (set in
/// `WindowState`); `scratchpadText` is already persisted.
struct DockedScratchpadPanel: View {

    @Binding var text: String
    @Binding var width: CGFloat

    @Environment(WindowState.self) private var windowState

    private static let minWidth: CGFloat = 200
    private static let maxWidth: CGFloat = 600

    var body: some View {
        HStack(spacing: 0) {
            // Left-edge resize handle
            Rectangle()
                .fill(SputnikColor.separator)
                .frame(width: 4)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let newWidth = width + value.translation.width
                            width = max(Self.minWidth, min(Self.maxWidth, newWidth))
                        }
                )
                .cursor(.resizeLeftRight)

            VStack(spacing: 0) {
                titleBar
                Divider()
                ScratchpadTextView(text: $text)
            }
            .frame(width: max(Self.minWidth, min(Self.maxWidth, width)))
        }
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack {
            Text("Scratchpad")
                .font(.system(size: SputnikFont.caption, weight: .semibold))
                .foregroundStyle(SputnikColor.primaryText)

            Spacer()

            Button(action: { windowState.scratchpadVisible = false }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(SputnikColor.secondaryText)
            .help("Close Scratchpad")
        }
        .padding(.horizontal, SputnikSpacing.sm)
        .padding(.vertical, 4)
        .background(SputnikColor.secondaryBackground)
    }
}

// MARK: - Cursor modifier for resize handle

private struct CursorModifier: ViewModifier {
    let cursor: NSCursor

    func body(content: Content) -> some View {
        content.onAppear {
            // The resize handle cursor is set via the DragGesture's hover behavior.
            // This modifier is intentionally minimalist for now.
        }
    }
}

extension View {
    fileprivate func cursor(_ cursor: NSCursor) -> some View {
        self.onContinuousHover { phase in
            switch phase {
            case .active:
                cursor.push()
            case .ended:
                NSCursor.pop()
            }
        }
    }
}
