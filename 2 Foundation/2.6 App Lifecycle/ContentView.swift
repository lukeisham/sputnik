import SwiftUI

/// Root layout that reserves every named panel slot and the pinned Terminal strip.
///
/// Each slot currently shows a placeholder `Color` view; the real panels (modules 3–8)
/// will replace these once they are built. The Terminal area is pinned at the bottom and
/// is not part of the slot system.
public struct ContentView: View {

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Main three-column area
            HStack(spacing: 1) {
                // Left slot
                slotPlaceholder(position: .left, color: .blue.opacity(0.10))

                // Centre column — upper and lower
                VStack(spacing: 1) {
                    slotPlaceholder(position: .centerUpper, color: .green.opacity(0.10))
                    slotPlaceholder(position: .centerLower, color: .purple.opacity(0.10))
                }

                // Right slot
                slotPlaceholder(position: .right, color: .orange.opacity(0.10))
            }

            Divider()

            // Terminal strip — always visible, not a relocatable slot
            terminalPlaceholder
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    // MARK: - Private helpers

    private func slotPlaceholder(position: PanelPosition, color: Color) -> some View {
        ZStack {
            color
            Text(position.rawValue)
                .font(.system(size: SputnikFont.caption, weight: .medium, design: .monospaced))
                .foregroundStyle(SputnikColor.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var terminalPlaceholder: some View {
        ZStack {
            SputnikColor.terminalBackground
            Text("Terminal (module 7)")
                .font(.system(size: SputnikFont.caption, weight: .medium, design: .monospaced))
                .foregroundStyle(SputnikColor.terminalForeground)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
    }
}
