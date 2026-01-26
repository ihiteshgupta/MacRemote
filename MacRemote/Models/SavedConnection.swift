import Foundation
import SwiftData

@Model
final class SavedConnection {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var lastConnected: Date?
    var isManual: Bool

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = 5900,
        lastConnected: Date? = nil,
        isManual: Bool = false
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.lastConnected = lastConnected
        self.isManual = isManual
    }
}

extension SavedConnection {
    var displayName: String {
        name.isEmpty ? host : name
    }

    var connectionString: String {
        "\(host):\(port)"
    }
}
