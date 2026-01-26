import Foundation
import Network

struct DiscoveredMac: Identifiable, Hashable {
    let id: UUID
    let name: String
    let host: String
    let port: Int
    let endpoint: NWEndpoint?

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = 5900,
        endpoint: NWEndpoint? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.endpoint = endpoint
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: DiscoveredMac, rhs: DiscoveredMac) -> Bool {
        lhs.id == rhs.id
    }

    func toSavedConnection() -> SavedConnection {
        SavedConnection(
            name: name,
            host: host,
            port: port,
            isManual: false
        )
    }
}
