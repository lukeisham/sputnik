import AppKit
import SwiftUI

struct SputnikMenuGroup: Commands {

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Sputnik") {
                openWindow(id: "about")
            }

            Divider()

            Button("Settings…") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Hide Sputnik") {
                NSApp.hide(nil)
            }
            .keyboardShortcut("h", modifiers: .command)

            Button("Hide Others") {
                NSApp.hideOtherApplications(nil)
            }
            .keyboardShortcut("h", modifiers: [.command, .option])

            Button("Show All") {
                NSApp.unhideAllApplications(nil)
            }

            Divider()

            Button("Quit Sputnik") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
