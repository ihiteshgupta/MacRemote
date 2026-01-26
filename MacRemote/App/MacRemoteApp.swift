import SwiftUI
import SwiftData

@main
struct ScreenControlApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: SavedConnection.self)
    }
}
