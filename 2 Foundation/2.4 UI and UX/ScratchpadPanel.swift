import SwiftUI

/// A resizable, draggable overlay panel anchored bottom-right of the content area.
/// Contains a plain-text NSTextView for unstructured note-taking.
///
/// **Default size:** 320 × 240 pt. **Minimum:** 200 × 120 pt.
/// Size and position persist across launches via UserDefaults.
///
/// - Note: Position is stored as an offset from the bottom-right corner, with
///   `scratchpadFrame.origin.x` representing the horizontal offset (positive = rightward)
///   and `scratchpadFrame.origin.y` representing the vertical offset (positive = upward).
///   A zero-origin frame places the panel flush at the bottom-right corner.
public struct ScratchpadPanel: View {

    @Binding var isVisible: Bool
    @Binding var text: String
    @Binding var scratchpadFrame: CGRect

    /// Temporary drag offset applied during an active drag gesture.
    @State private var dragOffset: CGSize = .zero

    private static let minSize = CGSize(width: 200, height: 120)
    private static let defaultSize = CGSize(width: 320, height: 240)

    public init(isVisible: Binding<Bool>, text: Binding<String>, scratchpadFrame: Binding<CGRect>) {
        self._isVisible = isVisible
        self._text = text
        self._scratchpadFrame = scratchpadFrame
    }

    public var body: some View {
        Group {
            if isVisible {
                VStack(spacing: 0) {
                    titleBar
                    Divider()
                    ScratchpadTextView(text: $text)
                    resizeHandle
                }
                .frame(
                    width: max(scratchpadFrame.width, Self.minSize.width),
                    height: max(scratchpadFrame.height, Self.minSize.height)
                )
                .background(SputnikColor.background)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(SputnikColor.separator, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 2)
                .offset(
                    x: scratchpadFrame.origin.x + dragOffset.width,
                    y: -(scratchpadFrame.origin.y + dragOffset.height)
                )
            }
        }
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack {
            Text("Scratchpad")
                .font(.system(size: SputnikFont.caption, weight: .semibold))
                .foregroundStyle(SputnikColor.primaryText)

            Spacer()

            Button(action: { isVisible = false }) {
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
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    // Commit the drag: positive x = rightward, positive y = upward
                    scratchpadFrame.origin.x = max(
                        0, scratchpadFrame.origin.x + value.translation.width)
                    scratchpadFrame.origin.y = max(
                        0, scratchpadFrame.origin.y - value.translation.height)
                    dragOffset = .zero
                }
        )
    }

    // MARK: - Resize handle

    private var resizeHandle: some View {
        HStack(spacing: 2) {
            Spacer()
            Image(systemName: "arrow.up.backward.and.arrow.down.forward")
                .font(.system(size: 8))
                .foregroundStyle(SputnikColor.secondaryText)
                .padding(.trailing, 4)
        }
        .frame(height: 12)
        .background(SputnikColor.secondaryBackground)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let newWidth = max(
                        Self.minSize.width, scratchpadFrame.width + value.translation.width)
                    // For a bottom-right anchored panel, drag upward (negative y in view coords)
                    // reduces height. We negate because offset's y is positive-up.
                    let newHeight = max(
                        Self.minSize.height, scratchpadFrame.height - value.translation.height)
                    scratchpadFrame.size.width = newWidth
                    scratchpadFrame.size.height = newHeight
                }
        )
    }
}
