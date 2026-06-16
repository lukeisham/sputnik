import SwiftUI

/// A simple SwiftUI view for displaying a summary result (or loading/error state)
/// inside an NSPopover.
///
/// Extracted from `EditorTextView` to honour SR-6 (one responsibility per file).
/// Used by `EditorTextView.summarizeSelectionLocally()` to present the result of
/// `ExtractiveSummarizer.summary(of:maxSentences:)`.
struct SummaryPopoverContent: View {
    let text: String
    let isLoading: Bool

    var body: some View {
        HStack {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.7)
                    .padding(.trailing, 4)
            }
            Text(text)
                .textSelection(.enabled)
                .font(.system(size: 12))
                .padding(8)
                .frame(maxWidth: 280, alignment: .leading)
        }
        .padding(4)
    }
}
