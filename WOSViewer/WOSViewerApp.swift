import SwiftUI

@main
struct WOSViewerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1100, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
