import SwiftUI

/// The SwiftUI find/replace bar that slides in below the tab bar when the user presses ⌘F.
///
/// All search logic lives in `SearchController`; this view is pure presentation (SR-6).
/// SwiftUI is appropriate here because the bar has no raw-AppKit requirements (SW-3).
public struct SearchBarView: View {

    @Bindable var controller: SearchController
    @State private var searchDebounceTask: Task<Void, Never>?

    public init(controller: SearchController) {
        self.controller = controller
    }

    public var body: some View {
        if controller.isVisible {
            VStack(spacing: 0) {
                Divider()
                VStack(spacing: 6) {
                    // Find row
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Find", text: $controller.searchTerm)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { controller.search() }
                            .onChange(of: controller.searchTerm) { _, _ in
                                // Debounce search on term change (300ms)
                                searchDebounceTask?.cancel()
                                searchDebounceTask = Task {
                                    try? await Task.sleep(nanoseconds: 300_000_000)
                                    controller.search()
                                }
                            }
                        Button(action: controller.previousMatch) {
                            Image(systemName: "chevron.left")
                        }
                        .help("Previous Match")
                        Button(action: controller.nextMatch) {
                            Image(systemName: "chevron.right")
                        }
                        .help("Next Match")
                        Button(action: controller.toggleVisible) {
                            Image(systemName: "xmark")
                        }
                        .help("Close")
                    }
                    // Replace row
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left.arrow.right")
                            .foregroundStyle(.secondary)
                        TextField("Replace", text: $controller.replaceTerm)
                            .textFieldStyle(.roundedBorder)
                        Button("Replace", action: controller.replaceCurrent)
                            .disabled(controller.matchRanges.isEmpty)
                        Button("All", action: controller.replaceAll)
                            .disabled(controller.matchRanges.isEmpty)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.bar)
                Divider()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
