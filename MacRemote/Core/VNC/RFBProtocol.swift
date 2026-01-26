import Foundation

// MARK: - RFB Protocol Constants

enum RFBVersion {
    static let v33 = "RFB 003.003\n"
    static let v37 = "RFB 003.007\n"
    static let v38 = "RFB 003.008\n"
}

enum RFBSecurityType: UInt8 {
    case invalid = 0
    case none = 1
    case vncAuth = 2
    case tight = 16
    case ultraVNC = 17
    case appleDH = 30      // Apple Remote Desktop
    case macOSAuth = 35    // macOS username/password
}

enum RFBClientMessageType: UInt8 {
    case setPixelFormat = 0
    case setEncodings = 2
    case framebufferUpdateRequest = 3
    case keyEvent = 4
    case pointerEvent = 5
    case clientCutText = 6
}

enum RFBServerMessageType: UInt8 {
    case framebufferUpdate = 0
    case setColorMapEntries = 1
    case bell = 2
    case serverCutText = 3
}

enum RFBEncoding: Int32, CustomStringConvertible {
    case raw = 0
    case copyRect = 1
    case rre = 2
    case hextile = 5
    case tight = 7
    case zrle = 16
    case cursor = -239
    case desktopSize = -223
    case jpeg = -260        // Tight JPEG quality
    case compressLevel = -247  // Tight compression

    var description: String {
        switch self {
        case .raw: return "Raw"
        case .copyRect: return "CopyRect"
        case .rre: return "RRE"
        case .hextile: return "Hextile"
        case .tight: return "Tight"
        case .zrle: return "ZRLE"
        case .cursor: return "Cursor"
        case .desktopSize: return "DesktopSize"
        case .jpeg: return "JPEG"
        case .compressLevel: return "CompressLevel"
        }
    }

    // Quality levels for Tight JPEG (add to -32 for quality 0-9)
    static func jpegQuality(_ level: Int) -> Int32 {
        return Int32(-32 + min(9, max(0, level)))
    }

    // Compression levels for Tight (add to -256 for level 0-9)
    static func compressionLevel(_ level: Int) -> Int32 {
        return Int32(-256 + min(9, max(0, level)))
    }
}

// MARK: - Pixel Format

struct PixelFormat {
    let bitsPerPixel: UInt8
    let depth: UInt8
    let bigEndian: Bool
    let trueColor: Bool
    let redMax: UInt16
    let greenMax: UInt16
    let blueMax: UInt16
    let redShift: UInt8
    let greenShift: UInt8
    let blueShift: UInt8

    static let rgb888 = PixelFormat(
        bitsPerPixel: 32,
        depth: 24,
        bigEndian: false,
        trueColor: true,
        redMax: 255,
        greenMax: 255,
        blueMax: 255,
        redShift: 16,
        greenShift: 8,
        blueShift: 0
    )

    static let rgb565 = PixelFormat(
        bitsPerPixel: 16,
        depth: 16,
        bigEndian: false,
        trueColor: true,
        redMax: 31,
        greenMax: 63,
        blueMax: 31,
        redShift: 11,
        greenShift: 5,
        blueShift: 0
    )

    func toBytes() -> Data {
        var data = Data(capacity: 16)
        data.append(bitsPerPixel)
        data.append(depth)
        data.append(bigEndian ? 1 : 0)
        data.append(trueColor ? 1 : 0)
        data.append(contentsOf: redMax.bigEndianBytes)
        data.append(contentsOf: greenMax.bigEndianBytes)
        data.append(contentsOf: blueMax.bigEndianBytes)
        data.append(redShift)
        data.append(greenShift)
        data.append(blueShift)
        data.append(contentsOf: [0, 0, 0]) // padding
        return data
    }

    static func from(data: Data) -> PixelFormat? {
        guard data.count >= 16 else { return nil }
        return PixelFormat(
            bitsPerPixel: data[0],
            depth: data[1],
            bigEndian: data[2] != 0,
            trueColor: data[3] != 0,
            redMax: UInt16(bigEndian: Data(data[4...5])),
            greenMax: UInt16(bigEndian: Data(data[6...7])),
            blueMax: UInt16(bigEndian: Data(data[8...9])),
            redShift: data[10],
            greenShift: data[11],
            blueShift: data[12]
        )
    }
}

// MARK: - Server Init

struct ServerInit {
    let width: UInt16
    let height: UInt16
    let pixelFormat: PixelFormat
    let name: String

    static func from(data: Data) -> ServerInit? {
        guard data.count >= 24 else { return nil }

        let width = UInt16(bigEndian: Data(data[0...1]))
        let height = UInt16(bigEndian: Data(data[2...3]))

        guard let pixelFormat = PixelFormat.from(data: Data(data[4...19])) else {
            return nil
        }

        let nameLength = UInt32(bigEndian: Data(data[20...23]))
        let nameEndIndex = 24 + Int(nameLength)

        guard data.count >= nameEndIndex else { return nil }

        let name = String(data: data[24..<nameEndIndex], encoding: .utf8) ?? "Unknown"

        return ServerInit(
            width: width,
            height: height,
            pixelFormat: pixelFormat,
            name: name
        )
    }
}

// MARK: - Framebuffer Update

struct FramebufferUpdateHeader {
    let numberOfRectangles: UInt16

    static func from(data: Data) -> FramebufferUpdateHeader? {
        guard data.count >= 3 else { return nil }
        // First byte is message type (0), second is padding
        let count = UInt16(bigEndian: Data(data[1...2]))
        return FramebufferUpdateHeader(numberOfRectangles: count)
    }
}

struct RectangleHeader {
    let x: UInt16
    let y: UInt16
    let width: UInt16
    let height: UInt16
    let encoding: Int32

    static let headerSize = 12

    static func from(data: Data) -> RectangleHeader? {
        guard data.count >= headerSize else { return nil }
        return RectangleHeader(
            x: UInt16(bigEndian: Data(data[0...1])),
            y: UInt16(bigEndian: Data(data[2...3])),
            width: UInt16(bigEndian: Data(data[4...5])),
            height: UInt16(bigEndian: Data(data[6...7])),
            encoding: Int32(bigEndian: Data(data[8...11]))
        )
    }
}

// MARK: - Extensions

extension UInt16 {
    var bigEndianBytes: [UInt8] {
        [UInt8((self >> 8) & 0xFF), UInt8(self & 0xFF)]
    }

    init(bigEndian data: Data) {
        self = (UInt16(data[0]) << 8) | UInt16(data[1])
    }
}

extension UInt32 {
    var bigEndianBytes: [UInt8] {
        [
            UInt8((self >> 24) & 0xFF),
            UInt8((self >> 16) & 0xFF),
            UInt8((self >> 8) & 0xFF),
            UInt8(self & 0xFF)
        ]
    }

    init(bigEndian data: Data) {
        self = (UInt32(data[0]) << 24) | (UInt32(data[1]) << 16) |
               (UInt32(data[2]) << 8) | UInt32(data[3])
    }
}

extension Int32 {
    var bigEndianBytes: [UInt8] {
        UInt32(bitPattern: self).bigEndianBytes
    }

    init(bigEndian data: Data) {
        self = Int32(bitPattern: UInt32(bigEndian: data))
    }
}
