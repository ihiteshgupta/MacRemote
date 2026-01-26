import SwiftUI

struct ContentView: View {
    @State private var selectedConnection: SavedConnection?
    @State private var isConnected = false

    var body: some View {
        Group {
            if isConnected, let connection = selectedConnection {
                SessionView(connection: connection, isConnected: $isConnected)
                    .transition(.opacity)
            } else {
                HomeView(
                    selectedConnection: $selectedConnection,
                    isConnected: $isConnected
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isConnected)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: SavedConnection.self, inMemory: true)
}
