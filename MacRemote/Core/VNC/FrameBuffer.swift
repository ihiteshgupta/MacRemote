import Foundation
import CoreGraphics
import UIKit

@MainActor
final class FrameBuffer: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var width: Int = 0
    @Published private(set) var height: Int = 0

    private var pixelData: [UInt8] = []
    private var pixelFormat: PixelFormat = .rgb888
    private let bytesPerPixel = 4

    // Batching: track dirty state and throttle image updates
    private var isDirty = false
    private var pendingUpdateWorkItem: DispatchWorkItem?
    private let updateThrottleInterval: TimeInterval = 0.016 // ~60fps max

    func initialize(width: Int, height: Int, pixelFormat: PixelFormat) {
        self.width = width
        self.height = height
        self.pixelFormat = pixelFormat
        self.pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        updateImageNow()
    }

    func updateRegion(x: Int, y: Int, width regionWidth: Int, height regionHeight: Int, data: Data) {
        guard !pixelData.isEmpty else { return }
        guard x >= 0, y >= 0, x < self.width, y < self.height else { return }

        let srcBytesPerPixel = Int(pixelFormat.bitsPerPixel) / 8

        // Clamp region to buffer bounds
        let clampedWidth = min(regionWidth, self.width - x)
        let clampedHeight = min(regionHeight, self.height - y)

        // Fast path: 32-bit BGRA with redShift=16 (most common from macOS Screen Sharing)
        if pixelFormat.bitsPerPixel == 32 && pixelFormat.redShift == 16 {
            updateRegionFast32(x: x, y: y, width: clampedWidth, height: clampedHeight, data: data)
        } else {
            updateRegionGeneric(x: x, y: y, width: clampedWidth, height: clampedHeight, data: data, srcBytesPerPixel: srcBytesPerPixel)
        }

        scheduleImageUpdate()
    }

    // Optimized path for 32-bit BGRA (bulk row copy)
    private func updateRegionFast32(x: Int, y: Int, width: Int, height: Int, data: Data) {
        data.withUnsafeBytes { srcBuffer in
            guard let srcBase = srcBuffer.baseAddress else { return }

            for row in 0..<height {
                let srcRowOffset = row * width * 4
                let dstRowOffset = ((y + row) * self.width + x) * 4

                guard srcRowOffset + width * 4 <= data.count else { continue }
                guard dstRowOffset + width * 4 <= pixelData.count else { continue }

                // Copy entire row at once, swapping BGR to RGB
                for col in 0..<width {
                    let srcPixelOffset = srcRowOffset + col * 4
                    let dstPixelOffset = dstRowOffset + col * 4

                    let srcPtr = srcBase.advanced(by: srcPixelOffset)
                    let b = srcPtr.load(fromByteOffset: 0, as: UInt8.self)
                    let g = srcPtr.load(fromByteOffset: 1, as: UInt8.self)
                    let r = srcPtr.load(fromByteOffset: 2, as: UInt8.self)

                    pixelData[dstPixelOffset] = r
                    pixelData[dstPixelOffset + 1] = g
                    pixelData[dstPixelOffset + 2] = b
                    pixelData[dstPixelOffset + 3] = 255
                }
            }
        }
    }

    // Generic path for other pixel formats
    private func updateRegionGeneric(x: Int, y: Int, width: Int, height: Int, data: Data, srcBytesPerPixel: Int) {
        for row in 0..<height {
            for col in 0..<width {
                let srcOffset = (row * width + col) * srcBytesPerPixel
                let dstX = x + col
                let dstY = y + row

                guard srcOffset + srcBytesPerPixel <= data.count else { continue }

                let dstOffset = (dstY * self.width + dstX) * bytesPerPixel

                let (r, g, b) = extractRGB(from: data, offset: srcOffset)

                pixelData[dstOffset] = r
                pixelData[dstOffset + 1] = g
                pixelData[dstOffset + 2] = b
                pixelData[dstOffset + 3] = 255
            }
        }
    }

    func copyRect(srcX: Int, srcY: Int, dstX: Int, dstY: Int, width: Int, height: Int) {
        guard !pixelData.isEmpty else { return }

        // Determine copy direction to handle overlapping regions
        let copyRowsForward = srcY < dstY || (srcY == dstY && srcX < dstX)

        if copyRowsForward {
            // Copy from bottom to top to handle downward overlap
            for row in stride(from: height - 1, through: 0, by: -1) {
                copyRow(srcX: srcX, srcY: srcY + row, dstX: dstX, dstY: dstY + row, width: width)
            }
        } else {
            // Copy from top to bottom
            for row in 0..<height {
                copyRow(srcX: srcX, srcY: srcY + row, dstX: dstX, dstY: dstY + row, width: width)
            }
        }

        scheduleImageUpdate()
    }

    private func copyRow(srcX: Int, srcY: Int, dstX: Int, dstY: Int, width: Int) {
        guard srcY >= 0, srcY < self.height, dstY >= 0, dstY < self.height else { return }

        let clampedSrcX = max(0, srcX)
        let clampedDstX = max(0, dstX)
        let adjustedWidth = min(width, min(self.width - clampedSrcX, self.width - clampedDstX))

        guard adjustedWidth > 0 else { return }

        let srcOffset = (srcY * self.width + clampedSrcX) * bytesPerPixel
        let dstOffset = (dstY * self.width + clampedDstX) * bytesPerPixel
        let bytesToCopy = adjustedWidth * bytesPerPixel

        // Use memmove for potentially overlapping regions
        pixelData.withUnsafeMutableBytes { buffer in
            guard let ptr = buffer.baseAddress else { return }
            memmove(ptr.advanced(by: dstOffset), ptr.advanced(by: srcOffset), bytesToCopy)
        }
    }

    private func extractRGB(from data: Data, offset: Int) -> (UInt8, UInt8, UInt8) {
        switch pixelFormat.bitsPerPixel {
        case 32:
            let b = data[offset]
            let g = data[offset + 1]
            let r = data[offset + 2]
            if pixelFormat.redShift == 0 {
                return (b, g, r)
            } else {
                return (r, g, b)
            }

        case 16:
            let byte1 = UInt16(data[offset])
            let byte2 = UInt16(data[offset + 1])
            let pixel = pixelFormat.bigEndian ? (byte1 << 8 | byte2) : (byte2 << 8 | byte1)

            let r = UInt8(((pixel >> pixelFormat.redShift) & pixelFormat.redMax) * 255 / pixelFormat.redMax)
            let g = UInt8(((pixel >> pixelFormat.greenShift) & pixelFormat.greenMax) * 255 / pixelFormat.greenMax)
            let b = UInt8(((pixel >> pixelFormat.blueShift) & pixelFormat.blueMax) * 255 / pixelFormat.blueMax)
            return (r, g, b)

        case 8:
            let gray = data[offset]
            return (gray, gray, gray)

        default:
            return (0, 0, 0)
        }
    }

    // Throttle image updates to avoid excessive UIImage creation
    private func scheduleImageUpdate() {
        isDirty = true

        // Cancel any pending update
        pendingUpdateWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.flushImageUpdate()
            }
        }
        pendingUpdateWorkItem = workItem

        DispatchQueue.main.asyncAfter(deadline: .now() + updateThrottleInterval, execute: workItem)
    }

    private func flushImageUpdate() {
        guard isDirty else { return }
        isDirty = false
        updateImageNow()
    }

    private func updateImageNow() {
        guard !pixelData.isEmpty, width > 0, height > 0 else { return }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        // Create a copy of pixel data for thread safety
        let dataCopy = pixelData
        guard let provider = CGDataProvider(data: Data(dataCopy) as CFData) else { return }

        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * bytesPerPixel,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return }

        image = UIImage(cgImage: cgImage)
    }

    // Force immediate update (for full screen refresh)
    func forceUpdate() {
        pendingUpdateWorkItem?.cancel()
        isDirty = false
        updateImageNow()
    }

    func clear() {
        pendingUpdateWorkItem?.cancel()
        pixelData = []
        width = 0
        height = 0
        image = nil
        isDirty = false
    }
}
