import Foundation
import Network
import Combine

enum VNCError: Error, LocalizedError {
    case connectionFailed(String)
    case handshakeFailed(String)
    case authenticationRequired
    case authenticationFailed
    case protocolError(String)
    case disconnected

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .handshakeFailed(let msg): return "Handshake failed: \(msg)"
        case .authenticationRequired: return "Authentication required"
        case .authenticationFailed: return "Authentication failed"
        case .protocolError(let msg): return "Protocol error: \(msg)"
        case .disconnected: return "Disconnected from server"
        }
    }
}

enum VNCState: Equatable {
    case disconnected
    case connecting
    case handshaking
    case authenticating
    case connected
    case error(String)
}

@MainActor
final class VNCClient: ObservableObject {
    @Published private(set) var state: VNCState = .disconnected
    @Published private(set) var serverName: String = ""
    @Published var frameBuffer = FrameBuffer()

    private var connection: NWConnection?
    private var serverInit: ServerInit?
    private var pixelFormat: PixelFormat = .rgb888
    private let queue = DispatchQueue(label: "com.macremote.vnc")

    private var receiveBuffer = Data()
    private var password: String = ""
    private var pendingAuth: ((String) -> Void)?

    // Preferred encodings in order - Raw is most reliable with macOS Screen Sharing
    private let preferredEncodings: [RFBEncoding] = [
        .copyRect,  // Efficient for moving regions
        .raw,       // Most compatible
        .desktopSize  // Pseudo-encoding for resize notification
    ]

    // MARK: - Public API

    func connect(host: String, port: Int) {
        disconnect()

        state = .connecting

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: UInt16(port))
        )

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        connection = NWConnection(to: endpoint, using: parameters)

        connection?.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in
                self?.handleConnectionState(newState)
            }
        }

        connection?.start(queue: queue)
    }

    func authenticate(password: String) {
        self.password = password
        pendingAuth?(password)
        pendingAuth = nil
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        state = .disconnected
        serverName = ""
        receiveBuffer.removeAll()
        frameBuffer.clear()
    }

    func requestFullUpdate() {
        guard state == .connected, let serverInit = serverInit else { return }
        sendFramebufferUpdateRequest(
            incremental: false,
            x: 0, y: 0,
            width: Int(serverInit.width),
            height: Int(serverInit.height)
        )
    }

    func sendMouseEvent(_ event: MouseEvent) {
        guard state == .connected else {
            print("Mouse event ignored - not connected")
            return
        }

        print("Sending mouse: x=\(event.x), y=\(event.y), buttons=\(event.buttonMask)")

        var data = Data(capacity: 6)
        data.append(RFBClientMessageType.pointerEvent.rawValue)
        data.append(event.buttonMask)
        data.append(contentsOf: event.x.bigEndianBytes)
        data.append(contentsOf: event.y.bigEndianBytes)

        send(data)
    }

    func sendKeyEvent(_ event: KeyEvent) {
        guard state == .connected else {
            print("Key event ignored - not connected")
            return
        }

        print("Sending key: \(event.key) pressed=\(event.isPressed)")

        var data = Data(capacity: 8)
        data.append(RFBClientMessageType.keyEvent.rawValue)
        data.append(event.isPressed ? 1 : 0)
        data.append(contentsOf: [0, 0])  // padding
        data.append(contentsOf: event.key.bigEndianBytes)

        send(data)
    }

    // MARK: - Connection State

    private func handleConnectionState(_ newState: NWConnection.State) {
        switch newState {
        case .ready:
            state = .handshaking
            startHandshake()

        case .failed(let error):
            state = .error(error.localizedDescription)

        case .cancelled:
            state = .disconnected

        default:
            break
        }
    }

    // MARK: - Handshake

    private func startHandshake() {
        receive(length: 12) { [weak self] data in
            self?.handleServerVersion(data)
        }
    }

    private func handleServerVersion(_ data: Data) {
        guard let version = String(data: data, encoding: .ascii) else {
            state = .error("Invalid server version received")
            return
        }

        let versionStr = version.trimmingCharacters(in: .whitespacesAndNewlines)
        print("VNC Server version: \(versionStr)")

        // Apple uses RFB 003.889, we respond with 003.008 (standard highest)
        // Some servers prefer if we echo their version, but 3.8 should work
        let clientVersion = "RFB 003.008\n"
        print("Sending client version: \(clientVersion.trimmingCharacters(in: .newlines))")
        send(Data(clientVersion.utf8))

        // Receive security types
        receive(length: 1) { [weak self] data in
            let count = Int(data[0])
            if count == 0 {
                // Security error - read reason
                self?.receiveSecurityError()
            } else {
                self?.receive(length: count) { typeData in
                    self?.handleSecurityTypes(typeData)
                }
            }
        }
    }

    private func receiveSecurityError() {
        receive(length: 4) { [weak self] lengthData in
            let length = UInt32(bigEndian: lengthData)
            self?.receive(length: Int(length)) { reasonData in
                let reason = String(data: reasonData, encoding: .utf8) ?? "Unknown error"
                self?.state = .error(reason)
            }
        }
    }

    private func handleSecurityTypes(_ data: Data) {
        print("Raw security type bytes: \(Array(data))")

        var types: [RFBSecurityType] = []
        for byte in data {
            if let type = RFBSecurityType(rawValue: byte) {
                types.append(type)
                print("  Recognized type \(byte): \(type)")
            } else {
                print("  Unknown type \(byte)")
            }
        }

        print("Supported security types: \(types.map { "\($0)" }.joined(separator: ", "))")

        guard let selectedType = RFBAuth.chooseBestSecurityType(types) else {
            state = .error("No supported security type")
            return
        }

        print("Selected security type: \(selectedType)")

        // Send selected type
        send(Data([selectedType.rawValue]))

        switch selectedType {
        case .none:
            // No auth needed, proceed to security result (3.8 requires it)
            receiveSecurityResult()

        case .vncAuth:
            print("VNC Auth selected - waiting for 16-byte challenge...")
            state = .authenticating
            // Receive 16-byte challenge
            receive(length: 16) { [weak self] challenge in
                print("Received VNC challenge: \(challenge.count) bytes")
                self?.handleVNCAuthChallenge(challenge)
            }

        case .appleDH, .macOSAuth:
            // Apple Remote Desktop / macOS authentication
            // These require complex Diffie-Hellman crypto - show helpful message
            let availableTypes = types.map { "\($0)" }.joined(separator: ", ")
            state = .error("Your Mac requires Apple authentication (ARD).\n\nAvailable types: \(availableTypes)\n\nTo connect, please enable VNC password on your Mac:\n\n1. System Settings → General → Sharing\n2. Click (i) next to Screen Sharing\n3. Enable 'VNC viewers may control screen with password'\n4. Set a password")

        default:
            let availableTypes = types.map { "\($0)" }.joined(separator: ", ")
            state = .error("Security type \(selectedType) not supported.\n\nAvailable: \(availableTypes)\n\nPlease enable 'VNC viewers may control screen with password' in Screen Sharing settings.")
        }
    }


    private func handleVNCAuthChallenge(_ challenge: Data) {
        if !password.isEmpty {
            performVNCAuth(challenge: challenge, password: password)
        } else {
            // Request password from UI
            pendingAuth = { [weak self] password in
                self?.performVNCAuth(challenge: challenge, password: password)
            }
        }
    }

    private func performVNCAuth(challenge: Data, password: String) {
        let response = RFBAuth.vncAuth(challenge: challenge, password: password)
        send(response)
        receiveSecurityResult()
    }

    private func receiveSecurityResult() {
        receive(length: 4) { [weak self] data in
            let result = UInt32(bigEndian: data)
            if result == 0 {
                self?.sendClientInit()
            } else {
                // Read error reason if available (3.8)
                self?.receive(length: 4) { lengthData in
                    let length = UInt32(bigEndian: lengthData)
                    if length > 0 && length < 1000 {
                        self?.receive(length: Int(length)) { reasonData in
                            let reason = String(data: reasonData, encoding: .utf8) ?? "Authentication failed"
                            self?.state = .error(reason)
                        }
                    } else {
                        self?.state = .error("Authentication failed")
                    }
                }
            }
        }
    }

    // MARK: - Client/Server Init

    private func sendClientInit() {
        // Shared flag: 1 = allow other clients
        send(Data([1]))

        // Receive ServerInit (minimum 24 bytes + name)
        receive(length: 24) { [weak self] data in
            self?.handleServerInitHeader(data)
        }
    }

    private func handleServerInitHeader(_ data: Data) {
        let width = UInt16(bigEndian: Data(data[0...1]))
        let height = UInt16(bigEndian: Data(data[2...3]))
        let nameLength = UInt32(bigEndian: Data(data[20...23]))

        receive(length: Int(nameLength)) { [weak self] nameData in
            let name = String(data: nameData, encoding: .utf8) ?? "Unknown"

            guard let pixelFormat = PixelFormat.from(data: Data(data[4...19])) else {
                self?.state = .error("Invalid pixel format")
                return
            }

            self?.serverInit = ServerInit(
                width: width,
                height: height,
                pixelFormat: pixelFormat,
                name: name
            )
            self?.serverName = name

            self?.frameBuffer.initialize(
                width: Int(width),
                height: Int(height),
                pixelFormat: pixelFormat
            )

            self?.sendPixelFormat()
            self?.sendEncodings()
            self?.state = .connected
            self?.requestFullUpdate()
            self?.startReceivingUpdates()
        }
    }

    private func sendPixelFormat() {
        var data = Data(capacity: 20)
        data.append(RFBClientMessageType.setPixelFormat.rawValue)
        data.append(contentsOf: [0, 0, 0])  // padding
        data.append(pixelFormat.toBytes())
        send(data)
    }

    private func sendEncodings() {
        var data = Data()
        data.append(RFBClientMessageType.setEncodings.rawValue)
        data.append(0)  // padding
        data.append(contentsOf: UInt16(preferredEncodings.count).bigEndianBytes)

        for encoding in preferredEncodings {
            data.append(contentsOf: encoding.rawValue.bigEndianBytes)
        }

        send(data)
    }

    private func sendFramebufferUpdateRequest(incremental: Bool, x: Int, y: Int, width: Int, height: Int) {
        var data = Data(capacity: 10)
        data.append(RFBClientMessageType.framebufferUpdateRequest.rawValue)
        data.append(incremental ? 1 : 0)
        data.append(contentsOf: UInt16(x).bigEndianBytes)
        data.append(contentsOf: UInt16(y).bigEndianBytes)
        data.append(contentsOf: UInt16(width).bigEndianBytes)
        data.append(contentsOf: UInt16(height).bigEndianBytes)
        send(data)
    }

    // MARK: - Receive Updates

    private func startReceivingUpdates() {
        receiveServerMessage()
    }

    private func receiveServerMessage() {
        guard state == .connected else { return }

        receive(length: 1) { [weak self] data in
            guard let type = RFBServerMessageType(rawValue: data[0]) else {
                print("Unknown message type: \(data[0])")
                self?.receiveServerMessage()
                return
            }

            switch type {
            case .framebufferUpdate:
                self?.receiveFramebufferUpdate()
            case .bell:
                // Ignore bell
                self?.receiveServerMessage()
            case .serverCutText:
                self?.receiveServerCutText()
            case .setColorMapEntries:
                // Skip color map
                self?.receiveServerMessage()
            }
        }
    }

    private func receiveFramebufferUpdate() {
        receive(length: 3) { [weak self] data in
            // 1 byte padding + 2 bytes rectangle count
            let count = UInt16(bigEndian: Data(data[1...2]))
            print("Receiving framebuffer update with \(count) rectangles")
            self?.receiveRectangles(remaining: Int(count))
        }
    }

    private func receiveRectangles(remaining: Int) {
        guard remaining > 0 else {
            // Request next update
            if let serverInit = serverInit {
                sendFramebufferUpdateRequest(
                    incremental: true,
                    x: 0, y: 0,
                    width: Int(serverInit.width),
                    height: Int(serverInit.height)
                )
            }
            receiveServerMessage()
            return
        }

        receive(length: RectangleHeader.headerSize) { [weak self] data in
            guard let header = RectangleHeader.from(data: data) else {
                self?.state = .error("Invalid rectangle header")
                return
            }

            self?.receiveRectangleData(header: header, remaining: remaining)
        }
    }

    private func receiveRectangleData(header: RectangleHeader, remaining: Int) {
        let encoding = RFBEncoding(rawValue: header.encoding)

        print("Rectangle: \(header.width)x\(header.height) at (\(header.x),\(header.y)) encoding=\(header.encoding) (\(encoding?.description ?? "unknown"))")

        switch encoding {
        case .raw:
            let dataSize = Int(header.width) * Int(header.height) * (Int(pixelFormat.bitsPerPixel) / 8)
            receive(length: dataSize) { [weak self] data in
                self?.frameBuffer.updateRegion(
                    x: Int(header.x),
                    y: Int(header.y),
                    width: Int(header.width),
                    height: Int(header.height),
                    data: data
                )
                self?.receiveRectangles(remaining: remaining - 1)
            }

        case .copyRect:
            receive(length: 4) { [weak self] data in
                let srcX = UInt16(bigEndian: Data(data[0...1]))
                let srcY = UInt16(bigEndian: Data(data[2...3]))
                self?.frameBuffer.copyRect(
                    srcX: Int(srcX),
                    srcY: Int(srcY),
                    dstX: Int(header.x),
                    dstY: Int(header.y),
                    width: Int(header.width),
                    height: Int(header.height)
                )
                self?.receiveRectangles(remaining: remaining - 1)
            }

        case .desktopSize:
            // Server is telling us new desktop size
            frameBuffer.initialize(
                width: Int(header.width),
                height: Int(header.height),
                pixelFormat: pixelFormat
            )
            receiveRectangles(remaining: remaining - 1)

        default:
            // Skip unknown encoding - try to continue
            print("Unsupported encoding: \(header.encoding)")
            receiveRectangles(remaining: remaining - 1)
        }
    }

    private func receiveServerCutText() {
        receive(length: 7) { [weak self] data in
            // 3 bytes padding + 4 bytes length
            let length = UInt32(bigEndian: Data(data[3...6]))
            self?.receive(length: Int(length)) { _ in
                // Ignore clipboard text for now
                self?.receiveServerMessage()
            }
        }
    }

    // MARK: - Network I/O

    private func send(_ data: Data) {
        connection?.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("Send error: \(error)")
            }
        })
    }

    private func receive(length: Int, completion: @escaping (Data) -> Void) {
        connection?.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] content, _, isComplete, error in
            Task { @MainActor in
                if let error = error {
                    self?.state = .error(error.localizedDescription)
                    return
                }

                if isComplete && content == nil {
                    self?.state = .disconnected
                    return
                }

                guard let data = content, data.count >= length else {
                    // Need more data
                    if let partial = content {
                        self?.receiveBuffer.append(partial)
                    }
                    self?.receive(length: length - (content?.count ?? 0), completion: completion)
                    return
                }

                completion(data)
            }
        }
    }
}
