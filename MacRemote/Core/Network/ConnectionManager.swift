import Foundation
import SwiftData
import Combine

@MainActor
final class ConnectionManager: ObservableObject {
    @Published var vncClient = VNCClient()
    @Published var quality = AdaptiveQuality()
    @Published var currentConnection: SavedConnection?

    private var modelContext: ModelContext?

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func connect(to mac: DiscoveredMac) {
        let connection = mac.toSavedConnection()
        connect(to: connection)
    }

    func connect(to connection: SavedConnection) {
        currentConnection = connection
        vncClient.connect(host: connection.host, port: connection.port)
    }

    func disconnect() {
        vncClient.disconnect()
        currentConnection = nil
        quality.reset()
    }

    func authenticate(password: String) {
        vncClient.authenticate(password: password)
    }

    func saveConnection(_ connection: SavedConnection) {
        connection.lastConnected = Date()
        modelContext?.insert(connection)
        try? modelContext?.save()
    }

    func updateLastConnected(_ connection: SavedConnection) {
        connection.lastConnected = Date()
        try? modelContext?.save()
    }

    func deleteConnection(_ connection: SavedConnection) {
        modelContext?.delete(connection)
        try? modelContext?.save()
    }

    func fetchSavedConnections() -> [SavedConnection] {
        let descriptor = FetchDescriptor<SavedConnection>(
            sortBy: [SortDescriptor(\.lastConnected, order: .reverse)]
        )
        return (try? modelContext?.fetch(descriptor)) ?? []
    }
}
