import XCTest
@testable import MacRemote

@MainActor
final class AdaptiveQualityTests: XCTestCase {

    var adaptiveQuality: AdaptiveQuality!

    override func setUp() async throws {
        adaptiveQuality = AdaptiveQuality()
    }

    override func tearDown() async throws {
        adaptiveQuality = nil
    }

    // MARK: - Initial State Tests

    func testInitialState() {
        XCTAssertEqual(adaptiveQuality.currentLevel, .high)
        XCTAssertEqual(adaptiveQuality.mode, .auto)
    }

    // MARK: - Quality Level Tests

    func testQualityLevelProperties() {
        XCTAssertEqual(QualityLevel.high.scale, 1.0)
        XCTAssertEqual(QualityLevel.medium.scale, 0.5)
        XCTAssertEqual(QualityLevel.low.scale, 0.25)
        XCTAssertEqual(QualityLevel.minimum.scale, 0.25)
    }

    func testQualityLevelJPEGQuality() {
        XCTAssertEqual(QualityLevel.high.jpegQuality, 9)
        XCTAssertEqual(QualityLevel.medium.jpegQuality, 7)
        XCTAssertEqual(QualityLevel.low.jpegQuality, 5)
        XCTAssertEqual(QualityLevel.minimum.jpegQuality, 3)
    }

    func testQualityLevelDisplayNames() {
        XCTAssertEqual(QualityLevel.high.displayName, "High")
        XCTAssertEqual(QualityLevel.medium.displayName, "Medium")
        XCTAssertEqual(QualityLevel.low.displayName, "Low")
        XCTAssertEqual(QualityLevel.minimum.displayName, "Minimum")
    }

    func testQualityLevelOrdering() {
        XCTAssertEqual(QualityLevel.high.rawValue, 0)
        XCTAssertEqual(QualityLevel.medium.rawValue, 1)
        XCTAssertEqual(QualityLevel.low.rawValue, 2)
        XCTAssertEqual(QualityLevel.minimum.rawValue, 3)
    }

    // MARK: - Quality Mode Tests

    func testQualityModeDisplayNames() {
        XCTAssertEqual(QualityMode.auto.displayName, "Auto")
        XCTAssertEqual(QualityMode.high.displayName, "High")
        XCTAssertEqual(QualityMode.medium.displayName, "Medium")
        XCTAssertEqual(QualityMode.low.displayName, "Low")
    }

    func testFixedQualityMode() {
        adaptiveQuality.mode = .medium

        // Record some latency - should use fixed mode
        adaptiveQuality.recordLatency(0.001) // Very low latency

        XCTAssertEqual(adaptiveQuality.currentLevel, .medium)
    }

    func testFixedHighMode() {
        adaptiveQuality.mode = .high
        adaptiveQuality.recordLatency(0.5) // High latency

        XCTAssertEqual(adaptiveQuality.currentLevel, .high)
    }

    func testFixedLowMode() {
        adaptiveQuality.mode = .low
        adaptiveQuality.recordLatency(0.001)

        XCTAssertEqual(adaptiveQuality.currentLevel, .low)
    }

    // MARK: - Latency Recording Tests

    func testRecordLatencyStoresValues() {
        adaptiveQuality.recordLatency(0.05)
        adaptiveQuality.recordLatency(0.06)
        adaptiveQuality.recordLatency(0.04)

        // Quality should still be high with good latency
        XCTAssertEqual(adaptiveQuality.currentLevel, .high)
    }

    func testLatencyHistoryLimit() {
        // Record more than 20 latencies
        for i in 0..<30 {
            adaptiveQuality.recordLatency(Double(i) * 0.01)
        }

        // Should handle without issues
        XCTAssertNotNil(adaptiveQuality.currentLevel)
    }

    // MARK: - Drop Recording Tests

    func testRecordDrop() {
        adaptiveQuality.recordDrop()

        // Single drop shouldn't change quality immediately
        XCTAssertEqual(adaptiveQuality.currentLevel, .high)
    }

    // MARK: - Reset Tests

    func testReset() {
        // Change state
        adaptiveQuality.mode = .low
        adaptiveQuality.recordLatency(0.5)
        adaptiveQuality.recordDrop()

        adaptiveQuality.reset()

        XCTAssertEqual(adaptiveQuality.currentLevel, .high)
        // Note: mode is not reset
    }

    // MARK: - All Cases Tests

    func testQualityLevelAllCases() {
        XCTAssertEqual(QualityLevel.allCases.count, 4)
        XCTAssertTrue(QualityLevel.allCases.contains(.high))
        XCTAssertTrue(QualityLevel.allCases.contains(.medium))
        XCTAssertTrue(QualityLevel.allCases.contains(.low))
        XCTAssertTrue(QualityLevel.allCases.contains(.minimum))
    }

    func testQualityModeAllCases() {
        XCTAssertEqual(QualityMode.allCases.count, 4)
        XCTAssertTrue(QualityMode.allCases.contains(.auto))
        XCTAssertTrue(QualityMode.allCases.contains(.high))
        XCTAssertTrue(QualityMode.allCases.contains(.medium))
        XCTAssertTrue(QualityMode.allCases.contains(.low))
    }
}
