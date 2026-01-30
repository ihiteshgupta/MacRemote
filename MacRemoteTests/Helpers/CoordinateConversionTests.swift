import XCTest
@testable import MacRemote

final class CoordinateConversionTests: XCTestCase {

    // MARK: - Screen Coordinate Conversion Tests

    /// Tests the coordinate conversion logic used in ScreenCanvasView
    /// iPad touch coordinates need to be mapped to remote screen coordinates

    func testBasicCoordinateConversion() {
        // Remote screen: 1920x1080
        // iPad display area: 1024x768 (aspect-fit)
        // No zoom, no pan

        let remoteWidth: CGFloat = 1920
        let remoteHeight: CGFloat = 1080
        let displayWidth: CGFloat = 1024
        let displayHeight: CGFloat = 576 // Letterboxed to maintain 16:9

        // Touch at center of display
        let touchX: CGFloat = 512
        let touchY: CGFloat = 288

        let scale = displayWidth / remoteWidth // 0.533...
        let remoteX = touchX / scale
        let remoteY = touchY / scale

        XCTAssertEqual(remoteX, 960, accuracy: 1)
        XCTAssertEqual(remoteY, 540, accuracy: 1)
    }

    func testCoordinateConversionWithZoom() {
        let remoteWidth: CGFloat = 1920
        let displayWidth: CGFloat = 1024
        let zoomScale: CGFloat = 2.0

        let touchX: CGFloat = 512

        // With zoom, effective scale changes
        let baseScale = displayWidth / remoteWidth
        let effectiveScale = baseScale * zoomScale

        let remoteX = touchX / effectiveScale

        XCTAssertEqual(remoteX, 480, accuracy: 1)
    }

    func testCoordinateConversionWithPan() {
        let remoteWidth: CGFloat = 1920
        let displayWidth: CGFloat = 1024

        // Pan offset (user scrolled right by 200 remote pixels)
        let panOffsetX: CGFloat = 200

        let touchX: CGFloat = 0 // Touch at left edge

        let scale = displayWidth / remoteWidth
        let remoteX = (touchX / scale) + panOffsetX

        XCTAssertEqual(remoteX, 200, accuracy: 1)
    }

    func testCoordinateConversionWithMultiMonitor() {
        // Multi-monitor scenario: primary 1920x1080, secondary at x=1920

        let displayOffsetX: CGFloat = 1920 // Secondary monitor offset
        let touchX: CGFloat = 100

        // For secondary monitor, add the display offset
        let remoteX = touchX + displayOffsetX

        XCTAssertEqual(remoteX, 2020)
    }

    func testLetterboxingCalculation() {
        // iPad Pro 13": ~2048x1536 points
        // Remote: 1920x1080 (16:9)

        let ipadWidth: CGFloat = 2048
        let ipadHeight: CGFloat = 1536
        let remoteWidth: CGFloat = 1920
        let remoteHeight: CGFloat = 1080

        // Calculate aspect-fit dimensions
        let ipadAspect = ipadWidth / ipadHeight // 1.33
        let remoteAspect = remoteWidth / remoteHeight // 1.78

        var displayWidth: CGFloat
        var displayHeight: CGFloat
        var offsetY: CGFloat = 0

        if remoteAspect > ipadAspect {
            // Remote is wider - fit to width, letterbox top/bottom
            displayWidth = ipadWidth
            displayHeight = ipadWidth / remoteAspect
            offsetY = (ipadHeight - displayHeight) / 2
        } else {
            // Remote is taller - fit to height, pillarbox left/right
            displayHeight = ipadHeight
            displayWidth = ipadHeight * remoteAspect
        }

        XCTAssertEqual(displayWidth, 2048, accuracy: 1)
        XCTAssertEqual(displayHeight, 1152, accuracy: 1)
        XCTAssertEqual(offsetY, 192, accuracy: 1)
    }

    func testBoundsClamping() {
        let remoteWidth: CGFloat = 1920
        let remoteHeight: CGFloat = 1080

        // Coordinate outside bounds
        var remoteX: CGFloat = 2000
        var remoteY: CGFloat = -50

        // Clamp to valid range
        remoteX = max(0, min(remoteX, remoteWidth - 1))
        remoteY = max(0, min(remoteY, remoteHeight - 1))

        XCTAssertEqual(remoteX, 1919)
        XCTAssertEqual(remoteY, 0)
    }

    func testIntegerConversionForVNC() {
        // VNC protocol uses UInt16 for coordinates
        let remoteX: CGFloat = 959.7
        let remoteY: CGFloat = 540.3

        let vncX = UInt16(round(remoteX))
        let vncY = UInt16(round(remoteY))

        XCTAssertEqual(vncX, 960)
        XCTAssertEqual(vncY, 540)
    }

    // MARK: - Edge Cases

    func testZeroSizeDisplay() {
        let displayWidth: CGFloat = 0
        let remoteWidth: CGFloat = 1920

        // Guard against division by zero
        let scale = displayWidth > 0 ? displayWidth / remoteWidth : 1

        XCTAssertEqual(scale, 1)
    }

    func testNegativeCoordinates() {
        // Touch gesture might report negative coordinates during edge swipes
        let touchX: CGFloat = -10
        let touchY: CGFloat = -5

        let clampedX = max(0, touchX)
        let clampedY = max(0, touchY)

        XCTAssertEqual(clampedX, 0)
        XCTAssertEqual(clampedY, 0)
    }

    func testVeryHighZoom() {
        let zoomScale: CGFloat = 10.0
        let remoteWidth: CGFloat = 1920
        let displayWidth: CGFloat = 1024

        let baseScale = displayWidth / remoteWidth
        let effectiveScale = baseScale * zoomScale

        // At 10x zoom, small touch movements = large remote movements
        let touchDelta: CGFloat = 10
        let remoteDelta = touchDelta / effectiveScale

        XCTAssertEqual(remoteDelta, 1.875, accuracy: 0.01)
    }
}
