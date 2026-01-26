import Foundation
import Network
import Combine

@MainActor
final class BonjourBrowser: ObservableObject {
    @Published private(set) var discoveredMacs: [DiscoveredMac] = []
    @Published private(set) var isSearching = false

    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "com.macremote.bonjour")

    // VNC service type
    private let serviceType = "_rfb._tcp"

    func startBrowsing() {
        guard browser == nil else { return }

        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let descriptor = NWBrowser.Descriptor.bonjour(type: serviceType, domain: "local.")
        browser = NWBrowser(for: descriptor, using: parameters)

        browser?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleStateUpdate(state)
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor in
                self?.handleResultsChanged(results: results, changes: changes)
            }
        }

        browser?.start(queue: queue)
        isSearching = true
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        isSearching = false
    }

    private func handleStateUpdate(_ state: NWBrowser.State) {
        switch state {
        case .ready:
            isSearching = true
        case .failed(let error):
            print("Bonjour browser failed: \(error)")
            isSearching = false
        case .cancelled:
            isSearching = false
        default:
            break
        }
    }

    private func handleResultsChanged(results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) {
        for result in results {
            if case .service(let name, _, _, _) = result.endpoint {
                // Check if we already have this service
                let cleanName = cleanServiceName(name)
                if !discoveredMacs.contains(where: { $0.name == cleanName }) {
                    // Resolve the IP address for this service
                    resolveService(result.endpoint, name: cleanName)
                }
            }
        }

        // Remove services that are no longer available
        for change in changes {
            if case .removed(let result) = change,
               case .service(let name, _, _, _) = result.endpoint {
                let cleanName = cleanServiceName(name)
                discoveredMacs.removeAll { $0.name == cleanName }
            }
        }
    }

    private func resolveService(_ endpoint: NWEndpoint, name: String) {
        let parameters = NWParameters.tcp
        let connection = NWConnection(to: endpoint, using: parameters)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let innerEndpoint = connection.currentPath?.remoteEndpoint,
                   case .hostPort(let host, let port) = innerEndpoint {
                    let hostString: String
                    switch host {
                    case .ipv4(let addr):
                        hostString = self?.ipv4ToString(addr) ?? ""
                    case .ipv6(let addr):
                        hostString = self?.ipv6ToString(addr) ?? ""
                    case .name(let nameStr, _):
                        hostString = nameStr
                    @unknown default:
                        hostString = ""
                    }

                    if !hostString.isEmpty {
                        Task { @MainActor in
                            let mac = DiscoveredMac(
                                name: name,
                                host: hostString,
                                port: Int(port.rawValue),
                                endpoint: endpoint
                            )
                            if !(self?.discoveredMacs.contains(where: { $0.name == name }) ?? true) {
                                self?.discoveredMacs.append(mac)
                                self?.discoveredMacs.sort { $0.name < $1.name }
                            }
                        }
                    }
                    connection.cancel()
                }
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }

        connection.start(queue: queue)

        // Timeout after 3 seconds
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            if connection.state != .ready && connection.state != .cancelled {
                connection.cancel()
            }
        }
    }

    private func cleanServiceName(_ name: String) -> String {
        // Remove common suffixes like "(2)" for duplicate names
        name.replacingOccurrences(of: "\\s*\\(\\d+\\)$", with: "", options: .regularExpression)
    }

    func resolveEndpoint(_ mac: DiscoveredMac, completion: @escaping (String?, Int?) -> Void) {
        guard let endpoint = mac.endpoint else {
            completion(mac.host, mac.port)
            return
        }

        let parameters = NWParameters.tcp
        let connection = NWConnection(to: endpoint, using: parameters)

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if let innerEndpoint = connection.currentPath?.remoteEndpoint,
                   case .hostPort(let host, let port) = innerEndpoint {
                    let hostString: String
                    switch host {
                    case .ipv4(let addr):
                        hostString = self.ipv4ToString(addr)
                    case .ipv6(let addr):
                        hostString = self.ipv6ToString(addr)
                    case .name(let name, _):
                        hostString = name
                    @unknown default:
                        hostString = mac.host
                    }
                    connection.cancel()
                    completion(hostString, Int(port.rawValue))
                }
            case .failed:
                connection.cancel()
                completion(nil, nil)
            default:
                break
            }
        }

        connection.start(queue: self.queue)

        // Timeout after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if connection.state != .ready {
                connection.cancel()
                completion(mac.host, mac.port)
            }
        }
    }

    private nonisolated func ipv4ToString(_ addr: IPv4Address) -> String {
        addr.debugDescription
    }

    private nonisolated func ipv6ToString(_ addr: IPv6Address) -> String {
        addr.debugDescription
    }
}
