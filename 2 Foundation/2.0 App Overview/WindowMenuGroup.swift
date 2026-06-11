import AppKit
import SwiftUI

struct WindowMenuGroup: Commands {

    private let appState: AppState
    private let router: AppInterPanelRouter

    @Environment(\.openWindow) private var openWindow

    init(appState: AppState, router: AppInterPanelRouter) {
        self.appState = appState
        self.router = router
    }

    var body: some Commands {
        Group {
            CommandGroup(replacing: .windowSize) {
                Button("Minimize") {
                    NSApp.keyWindow?.miniaturize(nil)
                }
                .keyboardShortcut("m", modifiers: .command)

                Button("Zoom") {
                    NSApp.keyWindow?.zoom(nil)
                }

                Divider()

                Button("Move Tab to New Window") {
                    // Route through the router so the dirty-guard fires for unsaved tabs (ISS-020).
                    Task {
                        if let newWindowID = await router.moveActiveTabToNewWindow() {
                            openWindow(id: "main", value: newWindowID)
                        }
                    }
                }

                Button("Merge All Windows") {
                    let allWindows = appState.orderedWindowIDs.compactMap {
                        appState.windowForID($0)
                    }
                    guard allWindows.count > 1 else { return }
                    guard let target = appState.activeWindow ?? allWindows.first else { return }
                    let windowsToMerge = allWindows.filter { $0.id != target.id }
                    for window in windowsToMerge {
                        for doc in window.openDocuments {
                            if !target.openDocuments.contains(where: {
                                $0.url == doc.url && $0.url != nil
                            }) {
                                target.openDocuments.append(doc)
                            }
                        }
                        // Close the NSWindow tagged with this WindowState's UUID (ISS-018).
                        // Windows are tagged via NSWindow.identifier in SputnikApp.onAppear.
                        if let nsWindow = NSApp.windows.first(where: {
                            $0.identifier?.rawValue == window.id.uuidString
                        }) {
                            nsWindow.close()
                        }
                        appState.closeWindow(window.id)
                    }
                    // Kill terminal PTYs after closing windows (killAllPTYs is async).
                    Task {
                        for window in windowsToMerge {
                            await window.terminalManager?.killAllPTYs()
                        }
                    }
                }
            }

            CommandGroup(replacing: .windowList) {}
        }
    }
}
