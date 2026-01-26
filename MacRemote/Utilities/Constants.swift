import Foundation

enum AppConstants {
    static let defaultPort = 5900
    static let bonjourServiceType = "_rfb._tcp"
    static let bonjourDomain = "local."

    // Timeouts
    static let connectionTimeout: TimeInterval = 10.0
    static let handshakeTimeout: TimeInterval = 5.0

    // Quality adjustment
    static let qualityAdjustmentInterval: TimeInterval = 2.0
    static let latencyThresholdHigh: TimeInterval = 0.05
    static let latencyThresholdLow: TimeInterval = 0.15
    static let dropRateThreshold: Double = 0.1
}
