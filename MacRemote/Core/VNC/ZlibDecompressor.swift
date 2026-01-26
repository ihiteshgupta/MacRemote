import Foundation
import Compression

final class ZlibDecompressor {
    private var buffer = Data()

    func decompress(_ data: Data) -> Data? {
        // Append new data to buffer
        buffer.append(data)

        // Try to decompress
        let decompressed = decompressZlib(buffer)

        if decompressed != nil {
            buffer.removeAll()
        }

        return decompressed
    }

    private func decompressZlib(_ data: Data) -> Data? {
        // Skip zlib header (2 bytes) if present
        var inputData = data
        if data.count >= 2 {
            let header = UInt16(data[0]) << 8 | UInt16(data[1])
            // Check for zlib header (CMF + FLG)
            if (header & 0x0F00) == 0x0800 && (header % 31) == 0 {
                inputData = Data(data.dropFirst(2))
            }
        }

        let destinationBufferSize = data.count * 10  // Estimate decompressed size
        var destinationBuffer = [UInt8](repeating: 0, count: destinationBufferSize)

        let decompressedSize = inputData.withUnsafeBytes { sourcePtr -> Int in
            guard let sourceBaseAddress = sourcePtr.baseAddress else { return 0 }

            return compression_decode_buffer(
                &destinationBuffer,
                destinationBufferSize,
                sourceBaseAddress.assumingMemoryBound(to: UInt8.self),
                inputData.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard decompressedSize > 0 else { return nil }

        return Data(destinationBuffer.prefix(decompressedSize))
    }

    func reset() {
        buffer.removeAll()
    }
}

// MARK: - ZRLE Decoder

@MainActor
final class ZRLEDecoder {
    private let decompressor = ZlibDecompressor()
    private let bytesPerPixel: Int

    init(bytesPerPixel: Int) {
        self.bytesPerPixel = bytesPerPixel
    }

    func decode(data: Data, x: Int, y: Int, width: Int, height: Int, into frameBuffer: FrameBuffer) {
        guard let decompressed = decompressor.decompress(data) else {
            print("ZRLE: Failed to decompress data")
            return
        }

        var offset = 0
        let tileSize = 64

        // Process tiles
        for tileY in stride(from: 0, to: height, by: tileSize) {
            for tileX in stride(from: 0, to: width, by: tileSize) {
                let tileW = min(tileSize, width - tileX)
                let tileH = min(tileSize, height - tileY)

                guard offset < decompressed.count else { return }

                offset = decodeTile(
                    data: decompressed,
                    offset: offset,
                    x: x + tileX,
                    y: y + tileY,
                    width: tileW,
                    height: tileH,
                    into: frameBuffer
                )
            }
        }
    }

    private func decodeTile(data: Data, offset: Int, x: Int, y: Int, width: Int, height: Int, into frameBuffer: FrameBuffer) -> Int {
        guard offset < data.count else { return offset }

        let subencoding = data[offset]
        var pos = offset + 1

        if subencoding == 0 {
            // Raw pixels
            let pixelCount = width * height
            let dataSize = pixelCount * bytesPerPixel
            guard pos + dataSize <= data.count else { return data.count }

            let pixelData = Data(data[pos..<(pos + dataSize)])
            frameBuffer.updateRegion(x: x, y: y, width: width, height: height, data: pixelData)
            return pos + dataSize

        } else if subencoding == 1 {
            // Solid tile (single color)
            guard pos + bytesPerPixel <= data.count else { return data.count }

            let colorData = Data(data[pos..<(pos + bytesPerPixel)])
            let solidData = Data(repeating: 0, count: width * height * bytesPerPixel)
            var mutableData = solidData

            // Fill with solid color
            for i in stride(from: 0, to: mutableData.count, by: bytesPerPixel) {
                for j in 0..<bytesPerPixel {
                    mutableData[i + j] = colorData[j]
                }
            }

            frameBuffer.updateRegion(x: x, y: y, width: width, height: height, data: mutableData)
            return pos + bytesPerPixel

        } else if subencoding >= 2 && subencoding <= 16 {
            // Packed palette
            let paletteSize = Int(subencoding)
            guard pos + paletteSize * bytesPerPixel <= data.count else { return data.count }

            // Read palette
            var palette = [[UInt8]]()
            for _ in 0..<paletteSize {
                var color = [UInt8]()
                for j in 0..<bytesPerPixel {
                    color.append(data[pos + j])
                }
                palette.append(color)
                pos += bytesPerPixel
            }

            // Calculate bits per index
            let bitsPerIndex: Int
            if paletteSize <= 2 {
                bitsPerIndex = 1
            } else if paletteSize <= 4 {
                bitsPerIndex = 2
            } else {
                bitsPerIndex = 4
            }

            // Decode packed pixels
            var pixelData = Data(capacity: width * height * bytesPerPixel)
            let mask = (1 << bitsPerIndex) - 1

            for row in 0..<height {
                var bitPos = 0
                var currentByte: UInt8 = 0

                for col in 0..<width {
                    if bitPos == 0 {
                        guard pos < data.count else { return data.count }
                        currentByte = data[pos]
                        pos += 1
                        bitPos = 8
                    }

                    bitPos -= bitsPerIndex
                    let index = Int((currentByte >> bitPos) & UInt8(mask))

                    if index < palette.count {
                        pixelData.append(contentsOf: palette[index])
                    } else {
                        pixelData.append(contentsOf: [UInt8](repeating: 0, count: bytesPerPixel))
                    }
                }
            }

            frameBuffer.updateRegion(x: x, y: y, width: width, height: height, data: pixelData)
            return pos

        } else if subencoding == 128 {
            // Plain RLE
            var pixelData = Data(capacity: width * height * bytesPerPixel)
            let totalPixels = width * height
            var pixelCount = 0

            while pixelCount < totalPixels && pos + bytesPerPixel <= data.count {
                // Read color
                var color = [UInt8]()
                for j in 0..<bytesPerPixel {
                    color.append(data[pos + j])
                }
                pos += bytesPerPixel

                // Read run length
                var runLength = 1
                if pos < data.count {
                    var rlByte = data[pos]
                    pos += 1
                    runLength = Int(rlByte) + 1

                    while rlByte == 255 && pos < data.count {
                        rlByte = data[pos]
                        pos += 1
                        runLength += Int(rlByte)
                    }
                }

                // Output pixels
                for _ in 0..<min(runLength, totalPixels - pixelCount) {
                    pixelData.append(contentsOf: color)
                }
                pixelCount += runLength
            }

            frameBuffer.updateRegion(x: x, y: y, width: width, height: height, data: pixelData)
            return pos

        } else if subencoding >= 130 {
            // Palette RLE
            let paletteSize = Int(subencoding) - 128
            guard pos + paletteSize * bytesPerPixel <= data.count else { return data.count }

            // Read palette
            var palette = [[UInt8]]()
            for _ in 0..<paletteSize {
                var color = [UInt8]()
                for j in 0..<bytesPerPixel {
                    color.append(data[pos + j])
                }
                palette.append(color)
                pos += bytesPerPixel
            }

            // Decode RLE
            var pixelData = Data(capacity: width * height * bytesPerPixel)
            let totalPixels = width * height
            var pixelCount = 0

            while pixelCount < totalPixels && pos < data.count {
                let indexByte = data[pos]
                pos += 1

                let index = Int(indexByte & 0x7F)
                let hasRunLength = (indexByte & 0x80) != 0

                var runLength = 1
                if hasRunLength {
                    runLength = 1
                    while pos < data.count {
                        let rlByte = data[pos]
                        pos += 1
                        runLength += Int(rlByte)
                        if rlByte != 255 { break }
                    }
                }

                // Output pixels
                let color = index < palette.count ? palette[index] : [UInt8](repeating: 0, count: bytesPerPixel)
                for _ in 0..<min(runLength, totalPixels - pixelCount) {
                    pixelData.append(contentsOf: color)
                }
                pixelCount += runLength
            }

            frameBuffer.updateRegion(x: x, y: y, width: width, height: height, data: pixelData)
            return pos
        }

        return pos
    }
}
