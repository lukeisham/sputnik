import SwiftUI
import CoreSputnik
import NetworkingSputnik
import UIComponentsSputnik

@main
struct App_SputnikApp: App {
    var body: some Scene {
        WindowGroup("Sputnik") {
            ContentView()
        }
        .windowToolbarStyle(.unified)
    }
}

struct ContentView: View {
    let client = HTTPClient()

    var body: some View {
        VStack(alignment: .leading) {
            TitleBar("Sputnik")
            Text("Core version: \(SputnikVersion.current)")
                .font(.subheadline)
            Divider()
            Text("Welcome to Sputnik. This is a placeholder UI.")
                .padding(.top, 8)
            Spacer()
        }
        .padding()
        .frame(minWidth: 640, minHeight: 420)
    }
}

#Preview {
    ContentView()
}
