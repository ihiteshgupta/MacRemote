import XCTest
@testable import MacRemote

final class RFBProtocolTests: XCTestCase {

    // MARK: - PixelFormat Tests

    func testPixelFormatRGB888Serialization() {
        let format = PixelFormat.rgb888
        let bytes = format.toBytes()

        XCTAssertEqual(bytes.count, 16)
        XCTAssertEqual(bytes[0], 32) // bitsPerPixel
        XCTAssertEqual(bytes[1], 24) // depth
        XCTAssertEqual(bytes[2], 0)  // bigEndian = false
        XCTAssertEqual(bytes[3], 1)  // trueColor = true
    }

    func testPixelFormatRGB565Serialization() {
        let format = PixelFormat.rgb565
        let bytes = format.toBytes()

        XCTAssertEqual(bytes[0], 16) // bitsPerPixel
        XCTAssertEqual(bytes[1], 16) // depth
    }

    func testPixelFormatDeserialization() {
        let original = PixelFormat.rgb888
        let bytes = original.toBytes()

        let restored = PixelFormat.from(data: bytes)

        XCTAssertNotNil(restored)
        XCTAssertEqual(restored?.bitsPerPixel, original.bitsPerPixel)
        XCTAssertEqual(restored?.depth, original.depth)
        XCTAssertEqual(restored?.redMax, original.redMax)
        XCTAssertEqual(restored?.greenMax, original.greenMax)
        XCTAssertEqual(restored?.blueMax, original.blueMax)
    }

    func testPixelFormatDeserializationWithInsufficientData() {
        let shortData = Data([0, 1, 2, 3, 4]) // Less than 16 bytes
        let format = PixelFormat.from(data: shortData)

        XCTAssertNil(format)
    }

    // MARK: - ServerInit Tests

    func testServerInitParsing() {
        // Build valid ServerInit data
        var data = Data()
        data.append(contentsOf: UInt16(1920).bigEndianBytes) // width
        data.append(contentsOf: UInt16(1080).bigEndianBytes) // height
        data.append(contentsOf: PixelFormat.rgb888.toBytes()) // 16 bytes
        data.append(contentsOf: UInt32(7).bigEndianBytes) // name length
        data.append(contentsOf: "TestMac".data(using: .utf8)!)

        let serverInit = ServerInit.from(data: data)

        XCTAssertNotNil(serverInit)
        XCTAssertEqual(serverInit?.width, 1920)
        XCTAssertEqual(serverInit?.height, 1080)
        XCTAssertEqual(serverInit?.name, "TestMac")
    }

    func testServerInitWithInsufficientData() {
        let shortData = Data([0, 1, 2, 3]) // Not enough bytes
        let serverInit = ServerInit.from(data: shortData)

        XCTAssertNil(serverInit)
    }

    // MARK: - RectangleHeader Tests

    func testRectangleHeaderParsing() {
        var data = Data()
        data.append(contentsOf: UInt16(100).bigEndianBytes)  // x
        data.append(contentsOf: UInt16(200).bigEndianBytes)  // y
        data.append(contentsOf: UInt16(640).bigEndianBytes)  // width
        data.append(contentsOf: UInt16(480).bigEndianBytes)  // height
        data.append(contentsOf: Int32(0).bigEndianBytes)     // encoding (Raw)

        let header = RectangleHeader.from(data: data)

        XCTAssertNotNil(header)
        XCTAssertEqual(header?.x, 100)
        XCTAssertEqual(header?.y, 200)
        XCTAssertEqual(header?.width, 640)
        XCTAssertEqual(header?.height, 480)
        XCTAssertEqual(header?.encoding, RFBEncoding.raw.rawValue)
    }

    func testRectangleHeaderSize() {
        XCTAssertEqual(RectangleHeader.headerSize, 12)
    }

    // MARK: - FramebufferUpdateHeader Tests

    func testFramebufferUpdateHeaderParsing() {
        var data = Data()
        data.append(0) // message type
        data.append(contentsOf: UInt16(5).bigEndianBytes) // numberOfRectangles

        let header = FramebufferUpdateHeader.from(data: data)

        XCTAssertNotNil(header)
        XCTAssertEqual(header?.numberOfRectangles, 5)
    }

    // MARK: - Encoding Tests

    func testRFBEncodingDescriptions() {
        XCTAssertEqual(RFBEncoding.raw.description, "Raw")
        XCTAssertEqual(RFBEncoding.copyRect.description, "CopyRect")
        XCTAssertEqual(RFBEncoding.zrle.description, "ZRLE")
        XCTAssertEqual(RFBEncoding.desktopSize.description, "DesktopSize")
    }

    func testJPEGQualityCalculation() {
        XCTAssertEqual(RFBEncoding.jpegQuality(0), -32)
        XCTAssertEqual(RFBEncoding.jpegQuality(9), -23)
        XCTAssertEqual(RFBEncoding.jpegQuality(5), -27)

        // Clamp tests
        XCTAssertEqual(RFBEncoding.jpegQuality(-5), -32) // Clamped to 0
        XCTAssertEqual(RFBEncoding.jpegQuality(100), -23) // Clamped to 9
    }

    func testCompressionLevelCalculation() {
        XCTAssertEqual(RFBEncoding.compressionLevel(0), -256)
        XCTAssertEqual(RFBEncoding.compressionLevel(9), -247)
    }

    // MARK: - Byte Extension Tests

    func testUInt16BigEndianBytes() {
        let value: UInt16 = 0x1234
        let bytes = value.bigEndianBytes

        XCTAssertEqual(bytes, [0x12, 0x34])
    }

    func testUInt16FromBigEndianData() {
        let data = Data([0x12, 0x34])
        let value = UInt16(bigEndian: data)

        XCTAssertEqual(value, 0x1234)
    }

    func testUInt32BigEndianBytes() {
        let value: UInt32 = 0x12345678
        let bytes = value.bigEndianBytes

        XCTAssertEqual(bytes, [0x12, 0x34, 0x56, 0x78])
    }

    func testUInt32FromBigEndianData() {
        let data = Data([0x12, 0x34, 0x56, 0x78])
        let value = UInt32(bigEndian: data)

        XCTAssertEqual(value, 0x12345678)
    }

    func testInt32BigEndianBytes() {
        let value: Int32 = -223 // DesktopSize encoding
        let bytes = value.bigEndianBytes
        let restored = Int32(bigEndian: Data(bytes))

        XCTAssertEqual(restored, value)
    }

    // MARK: - Security Type Tests

    func testSecurityTypeRawValues() {
        XCTAssertEqual(RFBSecurityType.none.rawValue, 1)
        XCTAssertEqual(RFBSecurityType.vncAuth.rawValue, 2)
        XCTAssertEqual(RFBSecurityType.appleDH.rawValue, 30)
    }

    // MARK: - Version String Tests

    func testRFBVersionStrings() {
        XCTAssertEqual(RFBVersion.v33, "RFB 003.003\n")
        XCTAssertEqual(RFBVersion.v37, "RFB 003.007\n")
        XCTAssertEqual(RFBVersion.v38, "RFB 003.008\n")

        // Verify length (12 characters including newline)
        XCTAssertEqual(RFBVersion.v38.count, 12)
    }
}
