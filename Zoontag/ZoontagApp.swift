import SwiftUI

@main
struct ZoontagApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .sidebar) {}
        }
    }
}
