import Foundation
import Network
@testable import MacRemote

/// Mock network connection for testing VNC client without actual network
final class MockNetworkConnection {

    enum State {
        case setup
        case preparing
        case ready
        case failed(Error)
        case cancelled
    }

    var state: State = .setup
    var receivedData: [Data] = []
    var sentData: [Data] = []

    var onStateChange: ((State) -> Void)?
    var onReceive: ((Data) -> Void)?

    private var responseQueue: [Data] = []

    // MARK: - Configuration

    func queueResponse(_ data: Data) {
        responseQueue.append(data)
    }

    func queueRFBHandshake() {
        // Queue RFB version
        queueResponse(Data(RFBVersion.v38.utf8))
    }

    func queueSecurityTypes(_ types: [RFBSecurityType]) {
        var data = Data()
        data.append(UInt8(types.count))
        for type in types {
            data.append(type.rawValue)
        }
        queueResponse(data)
    }

    func queueSecurityResult(success: Bool) {
        var data = Data()
        let result: UInt32 = success ? 0 : 1
        data.append(contentsOf: result.bigEndianBytes)
        queueResponse(data)
    }

    func queueServerInit(width: UInt16, height: UInt16, name: String) {
        var data = Data()
        data.append(contentsOf: width.bigEndianBytes)
        data.append(contentsOf: height.bigEndianBytes)
        data.append(contentsOf: PixelFormat.rgb888.toBytes())
        data.append(contentsOf: UInt32(name.count).bigEndianBytes)
        data.append(contentsOf: name.data(using: .utf8)!)
        queueResponse(data)
    }

    func queueVNCChallenge() {
        // 16 random bytes
        let challenge = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        queueResponse(challenge)
    }

    // MARK: - Simulated Operations

    func start() {
        state = .preparing
        onStateChange?(.preparing)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            self?.state = .ready
            self?.onStateChange?(.ready)
        }
    }

    func cancel() {
        state = .cancelled
        onStateChange?(.cancelled)
    }

    func send(_ data: Data, completion: @escaping (Error?) -> Void) {
        sentData.append(data)

        // Simulate async send
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) {
            completion(nil)
        }
    }

    func receive(minimumLength: Int, maximumLength: Int, completion: @escaping (Data?, Error?) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) { [weak self] in
            if let response = self?.responseQueue.first {
                self?.responseQueue.removeFirst()
                self?.receivedData.append(response)
                completion(response, nil)
            } else {
                // No data available
                completion(nil, nil)
            }
        }
    }

    // MARK: - Assertions

    func assertSentMessages(count: Int, file: StaticString = #file, line: UInt = #line) -> Bool {
        return sentData.count == count
    }

    func getLastSentData() -> Data? {
        return sentData.last
    }

    func clearSentData() {
        sentData.removeAll()
    }
}

// MARK: - Mock Bonjour Browser

final class MockBonjourBrowser {

    struct DiscoveredService {
        let name: String
        let host: String
        let port: UInt16
    }

    var discoveredServices: [DiscoveredService] = []
    var onServiceDiscovered: ((DiscoveredService) -> Void)?
    var onServiceRemoved: ((String) -> Void)?

    private var isScanning = false

    func startBrowsing() {
        isScanning = true

        // Simulate discovery after short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self, self.isScanning else { return }

            for service in self.discoveredServices {
                self.onServiceDiscovered?(service)
            }
        }
    }

    func stopBrowsing() {
        isScanning = false
    }

    func simulateServiceDiscovery(name: String, host: String, port: UInt16) {
        let service = DiscoveredService(name: name, host: host, port: port)
        discoveredServices.append(service)

        if isScanning {
            onServiceDiscovered?(service)
        }
    }

    func simulateServiceRemoval(name: String) {
        discoveredServices.removeAll { $0.name == name }

        if isScanning {
            onServiceRemoved?(name)
        }
    }
}

// MARK: - Test Data Generators

enum TestDataGenerator {

    static func framebufferUpdateWithRawEncoding(
        x: UInt16,
        y: UInt16,
        width: UInt16,
        height: UInt16
    ) -> Data {
        var data = Data()

        // Message type (framebuffer update)
        data.append(RFBServerMessageType.framebufferUpdate.rawValue)
        // Padding
        data.append(0)
        // Number of rectangles
        data.append(contentsOf: UInt16(1).bigEndianBytes)

        // Rectangle header
        data.append(contentsOf: x.bigEndianBytes)
        data.append(contentsOf: y.bigEndianBytes)
        data.append(contentsOf: width.bigEndianBytes)
        data.append(contentsOf: height.bigEndianBytes)
        data.append(contentsOf: RFBEncoding.raw.rawValue.bigEndianBytes)

        // Pixel data (4 bytes per pixel for rgb888)
        let pixelCount = Int(width) * Int(height)
        let pixelData = Data(repeating: 128, count: pixelCount * 4)
        data.append(pixelData)

        return data
    }

    static func desktopSizeUpdate(width: UInt16, height: UInt16) -> Data {
        var data = Data()

        data.append(RFBServerMessageType.framebufferUpdate.rawValue)
        data.append(0) // padding
        data.append(contentsOf: UInt16(1).bigEndianBytes) // 1 rectangle

        // Rectangle with desktop size encoding
        data.append(contentsOf: UInt16(0).bigEndianBytes) // x
        data.append(contentsOf: UInt16(0).bigEndianBytes) // y
        data.append(contentsOf: width.bigEndianBytes)
        data.append(contentsOf: height.bigEndianBytes)
        data.append(contentsOf: RFBEncoding.desktopSize.rawValue.bigEndianBytes)

        return data
    }

    static func bellMessage() -> Data {
        return Data([RFBServerMessageType.bell.rawValue])
    }

    static func serverCutText(_ text: String) -> Data {
        var data = Data()

        data.append(RFBServerMessageType.serverCutText.rawValue)
        data.append(contentsOf: [0, 0, 0]) // padding
        data.append(contentsOf: UInt32(text.count).bigEndianBytes)
        data.append(contentsOf: text.data(using: .isoLatin1) ?? Data())

        return data
    }
}
