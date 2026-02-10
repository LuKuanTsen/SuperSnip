import CoreGraphics
import Foundation

final class ImageStitcher {

    /// Stitch an array of overlapping frames into a single tall image.
    static func stitch(frames: [CGImage]) -> CGImage? {
        guard !frames.isEmpty else { return nil }
        guard frames.count >= 2 else { return frames.first }

        var result = frames[0]
        for i in 1..<frames.count {
            if let merged = stitchTwo(top: result, bottom: frames[i]) {
                result = merged
            }
            // If stitching fails, skip this frame rather than break the whole result
        }
        return result
    }

    /// Stitch two vertically overlapping images.
    /// `top` is the accumulated image so far, `bottom` is the new frame.
    private static func stitchTwo(top: CGImage, bottom: CGImage) -> CGImage? {
        guard top.width == bottom.width else { return nil }

        guard let topData = pixelData(for: top),
              let bottomData = pixelData(for: bottom) else { return nil }

        let width = top.width
        let topHeight = top.height
        let bottomHeight = bottom.height

        // Search for the best overlap between bottom of `top` and top of `bottom`.
        // We compare rows from the bottom portion of `top` with the top of `bottom`.
        let minOverlap = max(5, bottomHeight / 20)    // at least 5px or 5%
        let maxOverlap = bottomHeight * 9 / 10         // at most 90%
        // Only search within what the top image can provide
        let searchMax = min(maxOverlap, topHeight - 1)

        guard minOverlap < searchMax else {
            // Can't find meaningful overlap, just concatenate
            return concatenate(top: top, bottom: bottom, overlap: 0)
        }

        var bestOverlap = 0
        var bestScore = Double.infinity

        // For each candidate overlap, compare a few rows at that alignment
        for overlap in minOverlap...searchMax {
            let score = compareRows(
                topData: topData, topStartRow: topHeight - overlap,
                bottomData: bottomData, bottomStartRow: 0,
                width: width, rowCount: min(8, overlap),
                totalTopHeight: topHeight, totalBottomHeight: bottomHeight
            )
            if score < bestScore {
                bestScore = score
                bestOverlap = overlap
            }
        }

        // If the best match is too poor, there's no real overlap — just concatenate
        if bestScore > 25.0 {
            return concatenate(top: top, bottom: bottom, overlap: 0)
        }

        return concatenate(top: top, bottom: bottom, overlap: bestOverlap)
    }

    /// Compare `rowCount` rows at the given alignment.
    /// Returns average per-component difference (0 = identical, 255 = opposite).
    private static func compareRows(
        topData: Data, topStartRow: Int,
        bottomData: Data, bottomStartRow: Int,
        width: Int, rowCount: Int,
        totalTopHeight: Int, totalBottomHeight: Int
    ) -> Double {
        let bytesPerRow = width * 4
        var totalDiff: Int = 0
        var sampleCount = 0

        // Compare rows spread evenly through the overlap region
        for i in 0..<rowCount {
            let topRow = topStartRow + i
            let bottomRow = bottomStartRow + i

            guard topRow >= 0, topRow < totalTopHeight,
                  bottomRow >= 0, bottomRow < totalBottomHeight else { continue }

            let topOffset = topRow * bytesPerRow
            let bottomOffset = bottomRow * bytesPerRow

            guard topOffset + bytesPerRow <= topData.count,
                  bottomOffset + bytesPerRow <= bottomData.count else { continue }

            // Sample pixels across the row (every 4th pixel for speed)
            for x in stride(from: 0, to: bytesPerRow, by: 16) {
                totalDiff += abs(Int(topData[topOffset + x]) - Int(bottomData[bottomOffset + x]))
                totalDiff += abs(Int(topData[topOffset + x + 1]) - Int(bottomData[bottomOffset + x + 1]))
                totalDiff += abs(Int(topData[topOffset + x + 2]) - Int(bottomData[bottomOffset + x + 2]))
                sampleCount += 3
            }
        }

        return sampleCount > 0 ? Double(totalDiff) / Double(sampleCount) : Double.infinity
    }

    /// Vertically concatenate two images, removing `overlap` pixel rows from the seam.
    private static func concatenate(top: CGImage, bottom: CGImage, overlap: Int) -> CGImage? {
        let width = top.width
        let topHeight = top.height
        let bottomHeight = bottom.height
        let newHeight = topHeight + bottomHeight - overlap

        guard newHeight > 0 else { return nil }

        guard let ctx = CGContext(
            data: nil, width: width, height: newHeight,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // CG coordinate system: origin at bottom-left.
        // The bottom image goes at y=0 (visual bottom of final image).
        // The top image goes above it, offset by (bottomHeight - overlap).
        ctx.draw(bottom, in: CGRect(x: 0, y: 0, width: width, height: bottomHeight))
        ctx.draw(top, in: CGRect(x: 0, y: bottomHeight - overlap, width: width, height: topHeight))

        return ctx.makeImage()
    }

    /// Extract raw RGBA pixel data from a CGImage.
    private static func pixelData(for image: CGImage) -> Data? {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4

        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = ctx.data else { return nil }
        return Data(bytes: data, count: height * bytesPerRow)
    }
}
