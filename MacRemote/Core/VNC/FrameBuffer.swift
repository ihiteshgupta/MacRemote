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

    func initialize(width: Int, height: Int, pixelFormat: PixelFormat) {
        self.width = width
        self.height = height
        self.pixelFormat = pixelFormat
        self.pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        updateImage()
    }

    func updateRegion(x: Int, y: Int, width: Int, height: Int, data: Data) {
        guard !pixelData.isEmpty else { return }

        let srcBytesPerPixel = Int(pixelFormat.bitsPerPixel) / 8

        for row in 0..<height {
            for col in 0..<width {
                let srcOffset = (row * width + col) * srcBytesPerPixel
                let dstX = x + col
                let dstY = y + row

                guard dstX < self.width && dstY < self.height else { continue }
                guard srcOffset + srcBytesPerPixel <= data.count else { continue }

                let dstOffset = (dstY * self.width + dstX) * bytesPerPixel

                // Convert pixel to RGBA based on pixel format
                let (r, g, b) = extractRGB(from: data, offset: srcOffset)

                pixelData[dstOffset] = r
                pixelData[dstOffset + 1] = g
                pixelData[dstOffset + 2] = b
                pixelData[dstOffset + 3] = 255 // Alpha
            }
        }

        updateImage()
    }

    func copyRect(srcX: Int, srcY: Int, dstX: Int, dstY: Int, width: Int, height: Int) {
        guard !pixelData.isEmpty else { return }

        // Create temp buffer for the region
        var temp = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        // Copy source region to temp
        for row in 0..<height {
            for col in 0..<width {
                let sx = srcX + col
                let sy = srcY + row
                guard sx < self.width && sy < self.height else { continue }

                let srcOffset = (sy * self.width + sx) * bytesPerPixel
                let tempOffset = (row * width + col) * bytesPerPixel

                for i in 0..<bytesPerPixel {
                    temp[tempOffset + i] = pixelData[srcOffset + i]
                }
            }
        }

        // Copy temp to destination
        for row in 0..<height {
            for col in 0..<width {
                let dx = dstX + col
                let dy = dstY + row
                guard dx < self.width && dy < self.height else { continue }

                let dstOffset = (dy * self.width + dx) * bytesPerPixel
                let tempOffset = (row * width + col) * bytesPerPixel

                for i in 0..<bytesPerPixel {
                    pixelData[dstOffset + i] = temp[tempOffset + i]
                }
            }
        }

        updateImage()
    }

    private func extractRGB(from data: Data, offset: Int) -> (UInt8, UInt8, UInt8) {
        switch pixelFormat.bitsPerPixel {
        case 32:
            // Assuming BGRA or RGBA format
            let b = data[offset]
            let g = data[offset + 1]
            let r = data[offset + 2]
            // Respect pixel format shifts
            if pixelFormat.redShift == 0 {
                return (b, g, r) // BGR
            } else {
                return (r, g, b) // RGB
            }

        case 16:
            // RGB565
            let byte1 = UInt16(data[offset])
            let byte2 = UInt16(data[offset + 1])
            let pixel = pixelFormat.bigEndian ? (byte1 << 8 | byte2) : (byte2 << 8 | byte1)

            let r = UInt8(((pixel >> pixelFormat.redShift) & pixelFormat.redMax) * 255 / pixelFormat.redMax)
            let g = UInt8(((pixel >> pixelFormat.greenShift) & pixelFormat.greenMax) * 255 / pixelFormat.greenMax)
            let b = UInt8(((pixel >> pixelFormat.blueShift) & pixelFormat.blueMax) * 255 / pixelFormat.blueMax)
            return (r, g, b)

        case 8:
            // Grayscale or palette (simplified)
            let gray = data[offset]
            return (gray, gray, gray)

        default:
            return (0, 0, 0)
        }
    }

    private func updateImage() {
        guard !pixelData.isEmpty, width > 0, height > 0 else { return }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * bytesPerPixel,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return }

        guard let cgImage = context.makeImage() else { return }
        image = UIImage(cgImage: cgImage)
    }

    func clear() {
        pixelData = []
        width = 0
        height = 0
        image = nil
    }
}
