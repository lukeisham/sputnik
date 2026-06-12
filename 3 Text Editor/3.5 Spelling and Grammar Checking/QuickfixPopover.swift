import SwiftUI

/// The single-click quick-fix popover for a spelling or grammar issue (3.5).
///
/// Shown by `EditorTextView` (hosted in an `NSPopover`, the AppKit seam) when the user
/// single-clicks an underline. Presentation/layout stay in SwiftUI (SW-3); the Fix and
/// Dismiss callbacks are wired by the host to the `NSTextStorage` mutation and the
/// checker's ignore/re-check path respectively.
struct QuickfixPopover: View {

    /// `"Spelling"` or `"Grammar"`, shown as the popover header.
    let kindLabel: String

    /// Correction candidates, best first. May be empty for grammar-only descriptions.
    let suggestions: [String]

    /// Applies the chosen suggestion (replaces the underlined text).
    let onFix: (String) -> Void

    /// Dismisses the issue (ignore + re-check).
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kindLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            if suggestions.isEmpty {
                Text("No suggestion available")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(suggestions.prefix(5).enumerated()), id: \.offset) { _, suggestion in
                    Button {
                        onFix(suggestion)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 11))
                                .accessibilityHidden(true)
                            Text(suggestion)
                                .font(.system(size: 12, weight: .medium))
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Replace with \(suggestion)")
                }
            }

            Divider()

            Button {
                onDismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 11))
                        .accessibilityHidden(true)
                    Text("Dismiss")
                        .font(.system(size: 12))
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 220)
    }
}
