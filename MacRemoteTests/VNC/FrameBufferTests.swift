import XCTest
@testable import MacRemote

@MainActor
final class FrameBufferTests: XCTestCase {

    var frameBuffer: FrameBuffer!

    override func setUp() async throws {
        frameBuffer = FrameBuffer()
    }

    override func tearDown() async throws {
        frameBuffer = nil
    }

    // MARK: - Initialization Tests

    func testInitialization() {
        frameBuffer.initialize(width: 100, height: 100, pixelFormat: .rgb888)

        XCTAssertEqual(frameBuffer.width, 100)
        XCTAssertEqual(frameBuffer.height, 100)
        XCTAssertNotNil(frameBuffer.image)
    }

    func testInitializationWithZeroSize() {
        frameBuffer.initialize(width: 0, height: 0, pixelFormat: .rgb888)

        XCTAssertEqual(frameBuffer.width, 0)
        XCTAssertEqual(frameBuffer.height, 0)
    }

    func testInitializationWithRGB565() {
        frameBuffer.initialize(width: 50, height: 50, pixelFormat: .rgb565)

        XCTAssertEqual(frameBuffer.width, 50)
        XCTAssertEqual(frameBuffer.height, 50)
    }

    // MARK: - Region Update Tests

    func testUpdateRegion() {
        frameBuffer.initialize(width: 100, height: 100, pixelFormat: .rgb888)

        // Create red pixel data (BGRA format for rgb888 with redShift=16)
        var pixelData = Data()
        for _ in 0..<(10 * 10) {
            pixelData.append(contentsOf: [0, 0, 255, 255]) // Blue=0, Green=0, Red=255, Alpha=255
        }

        frameBuffer.updateRegion(x: 0, y: 0, width: 10, height: 10, data: pixelData)

        XCTAssertNotNil(frameBuffer.image)
    }

    func testUpdateRegionOutOfBounds() {
        frameBuffer.initialize(width: 50, height: 50, pixelFormat: .rgb888)

        // Try to update region outside buffer bounds
        var pixelData = Data(repeating: 255, count: 100 * 100 * 4)

        // Should not crash, just ignore out-of-bounds pixels
        frameBuffer.updateRegion(x: 40, y: 40, width: 100, height: 100, data: pixelData)

        XCTAssertNotNil(frameBuffer.image)
    }

    func testUpdateRegionWithEmptyBuffer() {
        // Don't initialize - buffer is empty
        let pixelData = Data(repeating: 255, count: 100)

        // Should handle gracefully without crash
        frameBuffer.updateRegion(x: 0, y: 0, width: 10, height: 10, data: pixelData)

        XCTAssertNil(frameBuffer.image)
    }

    // MARK: - CopyRect Tests

    func testCopyRect() {
        frameBuffer.initialize(width: 100, height: 100, pixelFormat: .rgb888)

        // First fill a region with color
        var redPixels = Data()
        for _ in 0..<(10 * 10) {
            redPixels.append(contentsOf: [0, 0, 255, 255])
        }
        frameBuffer.updateRegion(x: 0, y: 0, width: 10, height: 10, data: redPixels)

        // Copy that region to a new location
        frameBuffer.copyRect(srcX: 0, srcY: 0, dstX: 50, dstY: 50, width: 10, height: 10)

        XCTAssertNotNil(frameBuffer.image)
    }

    func testCopyRectWithEmptyBuffer() {
        // Should handle gracefully without crash
        frameBuffer.copyRect(srcX: 0, srcY: 0, dstX: 10, dstY: 10, width: 5, height: 5)

        XCTAssertNil(frameBuffer.image)
    }

    func testCopyRectOutOfBounds() {
        frameBuffer.initialize(width: 50, height: 50, pixelFormat: .rgb888)

        // Source partially out of bounds
        frameBuffer.copyRect(srcX: 45, srcY: 45, dstX: 0, dstY: 0, width: 20, height: 20)

        XCTAssertNotNil(frameBuffer.image)
    }

    // MARK: - Clear Tests

    func testClear() {
        frameBuffer.initialize(width: 100, height: 100, pixelFormat: .rgb888)
        XCTAssertNotNil(frameBuffer.image)

        frameBuffer.clear()

        XCTAssertEqual(frameBuffer.width, 0)
        XCTAssertEqual(frameBuffer.height, 0)
        XCTAssertNil(frameBuffer.image)
    }

    // MARK: - Pixel Format Tests

    func testRGB888PixelExtraction() {
        frameBuffer.initialize(width: 10, height: 10, pixelFormat: .rgb888)

        // RGBA pixel: Red=200, Green=100, Blue=50
        var pixelData = Data()
        for _ in 0..<(10 * 10) {
            pixelData.append(contentsOf: [50, 100, 200, 255]) // BGR order for rgb888
        }

        frameBuffer.updateRegion(x: 0, y: 0, width: 10, height: 10, data: pixelData)

        XCTAssertNotNil(frameBuffer.image)
    }

    func testRGB565PixelExtraction() {
        frameBuffer.initialize(width: 10, height: 10, pixelFormat: .rgb565)

        // RGB565 pixel
        var pixelData = Data()
        for _ in 0..<(10 * 10) {
            // RGB565: 5 bits red, 6 bits green, 5 bits blue
            let pixel: UInt16 = 0xF800 // Pure red
            pixelData.append(UInt8(pixel & 0xFF))
            pixelData.append(UInt8((pixel >> 8) & 0xFF))
        }

        frameBuffer.updateRegion(x: 0, y: 0, width: 10, height: 10, data: pixelData)

        XCTAssertNotNil(frameBuffer.image)
    }

    // MARK: - Performance Tests

    func testLargeFrameBufferPerformance() {
        measure {
            frameBuffer.initialize(width: 1920, height: 1080, pixelFormat: .rgb888)

            // Simulate full-screen update
            let pixelData = Data(repeating: 128, count: 1920 * 1080 * 4)
            frameBuffer.updateRegion(x: 0, y: 0, width: 1920, height: 1080, data: pixelData)
        }
    }

    func testMultipleSmallUpdatesPerformance() {
        frameBuffer.initialize(width: 1920, height: 1080, pixelFormat: .rgb888)

        measure {
            // Simulate multiple small region updates (typical VNC usage)
            let smallRegion = Data(repeating: 128, count: 64 * 64 * 4)
            for _ in 0..<50 {
                let x = Int.random(in: 0..<1856)
                let y = Int.random(in: 0..<1016)
                frameBuffer.updateRegion(x: x, y: y, width: 64, height: 64, data: smallRegion)
            }
        }
    }
}
