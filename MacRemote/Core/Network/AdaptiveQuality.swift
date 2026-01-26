import Foundation
import Combine

enum QualityLevel: Int, CaseIterable {
    case high = 0
    case medium = 1
    case low = 2
    case minimum = 3

    var displayName: String {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        case .minimum: return "Minimum"
        }
    }

    var scale: CGFloat {
        switch self {
        case .high: return 1.0
        case .medium: return 0.5
        case .low: return 0.25
        case .minimum: return 0.25
        }
    }

    var jpegQuality: Int {
        switch self {
        case .high: return 9
        case .medium: return 7
        case .low: return 5
        case .minimum: return 3
        }
    }
}

enum QualityMode: String, CaseIterable {
    case auto = "Auto"
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    var displayName: String { rawValue }
}

@MainActor
final class AdaptiveQuality: ObservableObject {
    @Published private(set) var currentLevel: QualityLevel = .high
    @Published var mode: QualityMode = .auto

    private var latencyHistory: [TimeInterval] = []
    private var dropCount = 0
    private var frameCount = 0
    private var lastAdjustment = Date()

    private let adjustmentInterval: TimeInterval = 2.0
    private let latencyThresholdHigh: TimeInterval = 0.05   // 50ms
    private let latencyThresholdLow: TimeInterval = 0.15    // 150ms
    private let dropThreshold: Double = 0.1                  // 10%

    func recordLatency(_ latency: TimeInterval) {
        latencyHistory.append(latency)
        if latencyHistory.count > 20 {
            latencyHistory.removeFirst()
        }
        frameCount += 1
        evaluateQuality()
    }

    func recordDrop() {
        dropCount += 1
        frameCount += 1
        evaluateQuality()
    }

    private func evaluateQuality() {
        guard mode == .auto else {
            // Use fixed quality
            currentLevel = fixedLevelForMode(mode)
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastAdjustment) >= adjustmentInterval else {
            return
        }

        lastAdjustment = now

        let avgLatency = latencyHistory.isEmpty ? 0 : latencyHistory.reduce(0, +) / Double(latencyHistory.count)
        let dropRate = frameCount > 0 ? Double(dropCount) / Double(frameCount) : 0

        // Reset counters
        dropCount = 0
        frameCount = 0

        // Decide quality level
        if avgLatency < latencyThresholdHigh && dropRate < dropThreshold {
            // Good conditions - increase quality
            increaseQuality()
        } else if avgLatency > latencyThresholdLow || dropRate > dropThreshold {
            // Poor conditions - decrease quality
            decreaseQuality()
        }
        // Otherwise maintain current level
    }

    private func increaseQuality() {
        if currentLevel.rawValue > 0 {
            currentLevel = QualityLevel(rawValue: currentLevel.rawValue - 1) ?? .high
        }
    }

    private func decreaseQuality() {
        if currentLevel.rawValue < QualityLevel.allCases.count - 1 {
            currentLevel = QualityLevel(rawValue: currentLevel.rawValue + 1) ?? .minimum
        }
    }

    private func fixedLevelForMode(_ mode: QualityMode) -> QualityLevel {
        switch mode {
        case .auto: return currentLevel
        case .high: return .high
        case .medium: return .medium
        case .low: return .low
        }
    }

    func reset() {
        latencyHistory.removeAll()
        dropCount = 0
        frameCount = 0
        currentLevel = .high
    }
}
