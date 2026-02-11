import CoreGraphics
import Foundation
import ImageIO

struct StitchDebugInfo {
    struct PairInfo {
        let frameIndex: Int
        let comparedAgainst: Int
        let thumbOverlap: Int
        let fullOverlap: Int
        let bestScore: Double
        let decision: String // "kept", "skipped (jitter)", "kept (no overlap)"
    }
    let pairs: [PairInfo]
    let validIndices: [Int]
    let validOverlaps: [Int]
    let frameCount: Int

    var log: String {
        var lines = [String]()
        lines.append("=== Stitch Debug ===")
        lines.append("Total frames: \(frameCount)")
        lines.append("")
        for p in pairs {
            lines.append("Frame \(p.frameIndex) vs \(p.comparedAgainst):")
            lines.append("  thumbOverlap=\(p.thumbOverlap), fullOverlap=\(p.fullOverlap), bestScore=\(String(format: "%.2f", p.bestScore))")
            lines.append("  -> \(p.decision)")
        }
        lines.append("")
        lines.append("Valid frames: \(validIndices)")
        lines.append("Overlaps (full-res px): \(validOverlaps)")
        return lines.joined(separator: "\n")
    }
}

final class ImageStitcher {

    private static let scaleFactor = 4

    /// Stitch frames using accumulated image comparison.
    ///
    /// Each new frame is compared against the accumulated result (thumbnail), not just
    /// the previous frame. This handles scroll bounce-back and page rebound:
    /// - If the new frame extends beyond the accumulated image → accept (forward scroll)
    /// - If the new frame is entirely within the accumulated image → skip (bounce back)
    static func stitchWithDebug(frames: [CGImage]) -> (image: CGImage?, debug: StitchDebugInfo) {
        let emptyDebug = StitchDebugInfo(pairs: [], validIndices: [0], validOverlaps: [], frameCount: frames.count)
        guard !frames.isEmpty else { return (nil, emptyDebug) }
        guard frames.count >= 2 else { return (frames.first, emptyDebug) }

        let thumbs = frames.map { downscale($0, by: scaleFactor) }

        var validIndices = [0]
        var validOverlaps = [Int]()
        var pairInfos = [StitchDebugInfo.PairInfo]()

        // Accumulated thumbnail — the stitched result so far at thumbnail scale.
        // We only keep the bottom portion (max 3× frame height) for bounded performance.
        guard var accThumb = thumbs[0] else { return (frames.first, emptyDebug) }
        let frameThumbHeight = accThumb.height

        for i in 1..<frames.count {
            guard let newThumb = thumbs[i] else {
                pairInfos.append(.init(
                    frameIndex: i, comparedAgainst: -1,
                    thumbOverlap: 0, fullOverlap: 0, bestScore: .infinity,
                    decision: "skipped (thumbnail failed)"
                ))
                continue
            }

            let (matchY, newContentRows, score) = findPositionInAccumulated(
                accumulated: accThumb, newFrame: newThumb
            )

            if matchY < 0 {
                // No match at all
                pairInfos.append(.init(
                    frameIndex: i, comparedAgainst: -1,
                    thumbOverlap: 0, fullOverlap: 0, bestScore: score,
                    decision: "skipped (no match in accumulated)"
                ))
                continue
            }

            // Require at least 3% new content to avoid accepting near-duplicates
            let minNewContent = max(2, newThumb.height * 3 / 100)
            if newContentRows < minNewContent {
                pairInfos.append(.init(
                    frameIndex: i, comparedAgainst: -1,
                    thumbOverlap: newThumb.height - newContentRows, fullOverlap: 0,
                    bestScore: score,
                    decision: "skipped (bounce back, \(newContentRows)px new < \(minNewContent)px min)"
                ))
                continue
            }

            // Accept frame — it has new content
            let fullNewContent = newContentRows * scaleFactor
            let fullOverlap = frames[i].height - fullNewContent
            let pct = fullOverlap * 100 / frames[i].height

            pairInfos.append(.init(
                frameIndex: i, comparedAgainst: -1,
                thumbOverlap: newThumb.height - newContentRows, fullOverlap: fullOverlap,
                bestScore: score,
                decision: "kept (overlap \(pct)%, +\(fullNewContent)px new)"
            ))

            validIndices.append(i)
            validOverlaps.append(fullOverlap)

            // Extend accumulated thumbnail with new content
            if let extended = extendAccumulated(accThumb, with: newThumb, newContentRows: newContentRows) {
                accThumb = extended
            }

            // Crop if too tall to keep comparison cost bounded
            let maxAccHeight = frameThumbHeight * 3
            if accThumb.height > maxAccHeight {
                if let cropped = cropBottom(accThumb, rows: frameThumbHeight * 2) {
                    accThumb = cropped
                }
            }
        }

        let debug = StitchDebugInfo(
            pairs: pairInfos,
            validIndices: validIndices,
            validOverlaps: validOverlaps,
            frameCount: frames.count
        )

        guard validIndices.count >= 2 else { return (frames.first, debug) }

        let validFrames = validIndices.map { frames[$0] }
        let result = compositeFrames(validFrames, overlaps: validOverlaps)
        return (result, debug)
    }

    /// Convenience wrapper without debug info.
    static func stitch(frames: [CGImage]) -> CGImage? {
        return stitchWithDebug(frames: frames).image
    }

    // MARK: - Composition

    private static func compositeFrames(_ frames: [CGImage], overlaps: [Int]) -> CGImage? {
        guard !frames.isEmpty else { return nil }
        let width = frames[0].width

        var totalHeight = frames[0].height
        for i in 1..<frames.count {
            totalHeight += frames[i].height - overlaps[i - 1]
        }
        guard totalHeight > 0 else { return nil }

        guard let ctx = CGContext(
            data: nil, width: width, height: totalHeight,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        var visualY = 0
        for i in 0..<frames.count {
            let frame = frames[i]
            let cgY = totalHeight - visualY - frame.height
            ctx.draw(frame, in: CGRect(x: 0, y: cgY, width: width, height: frame.height))
            if i < overlaps.count {
                visualY += frame.height - overlaps[i]
            }
        }

        return ctx.makeImage()
    }

    // MARK: - Overlap Detection

    /// Find overlap using 1D row-projection pre-filtering + full pixel verification.
    ///
    /// Algorithm:
    /// 1. Compute a 1D "brightness profile" (one scalar per row) for both images.
    /// 2. Use cheap 1D cross-correlation to find top N candidate overlap offsets.
    /// 3. Run expensive full-pixel compareRows only on those candidates.
    ///
    /// This reduces complexity from O(H² × W) to O(H²) + O(N × H × W) where N ≈ 10.
    private static func findOverlapWithScore(top: CGImage, bottom: CGImage) -> (overlap: Int, score: Double) {
        guard top.width == bottom.width else { return (0, .infinity) }
        guard let topData = pixelData(for: top),
              let bottomData = pixelData(for: bottom) else { return (0, .infinity) }

        let width = top.width
        let topHeight = top.height
        let bottomHeight = bottom.height

        let minOverlap = max(2, bottomHeight * 20 / 100)
        let maxOverlap = bottomHeight * 97 / 100
        let searchMax = min(maxOverlap, topHeight - 1)

        guard minOverlap < searchMax else { return (0, .infinity) }

        let bytesPerRow = width * 4
        let xMargin = min(20, width / 10) * 4

        // Step 1: Compute 1D brightness profile for each row
        let topProfile = rowProfile(data: topData, height: topHeight, bytesPerRow: bytesPerRow, xMargin: xMargin)
        let bottomProfile = rowProfile(data: bottomData, height: bottomHeight, bytesPerRow: bytesPerRow, xMargin: xMargin)

        // Step 2: Find candidate offsets via 1D cross-correlation (very cheap — scalar ops only)
        var candidates = [(overlap: Int, profileScore: Double)]()
        candidates.reserveCapacity(searchMax - minOverlap + 1)

        for overlap in stride(from: searchMax, through: minOverlap, by: -1) {
            let topStart = topHeight - overlap
            var sumSqDiff: Double = 0
            for r in 0..<overlap {
                let d = topProfile[topStart + r] - bottomProfile[r]
                sumSqDiff += d * d
            }
            let profileScore = sqrt(sumSqDiff / Double(overlap))
            candidates.append((overlap, profileScore))
        }

        // Step 3: Pick top N candidates (plus ±1 neighbors for sub-pixel robustness)
        candidates.sort { $0.profileScore < $1.profileScore }
        let topN = min(5, candidates.count)
        var verifySet = Set<Int>()
        for i in 0..<topN {
            let ov = candidates[i].overlap
            verifySet.insert(ov)
            if ov > minOverlap { verifySet.insert(ov - 1) }
            if ov < searchMax  { verifySet.insert(ov + 1) }
        }

        // Step 4: Full pixel verification only on selected candidates
        var bestOverlap = 0
        var bestScore = Double.infinity

        for overlap in verifySet {
            let score = compareRows(
                topData: topData, topStartRow: topHeight - overlap,
                bottomData: bottomData, bottomStartRow: 0,
                width: width, overlapHeight: overlap,
                totalTopHeight: topHeight, totalBottomHeight: bottomHeight
            )
            if score < bestScore {
                bestScore = score
                bestOverlap = overlap
            }
        }

        if bestScore <= 35.0 {
            return (bestOverlap, bestScore)
        }
        return (0, bestScore)
    }

    /// Compute average brightness per row — one scalar per row for fast 1D correlation.
    private static func rowProfile(data: Data, height: Int, bytesPerRow: Int, xMargin: Int) -> [Double] {
        var profile = [Double](repeating: 0, count: height)
        for row in 0..<height {
            let base = row * bytesPerRow
            var sum: Int = 0
            var count: Int = 0
            for x in stride(from: xMargin, to: bytesPerRow - xMargin, by: 16) {
                sum += Int(data[base + x]) + Int(data[base + x + 1]) + Int(data[base + x + 2])
                count += 3
            }
            profile[row] = count > 0 ? Double(sum) / Double(count) : 0
        }
        return profile
    }

    private static func compareRows(
        topData: Data, topStartRow: Int,
        bottomData: Data, bottomStartRow: Int,
        width: Int, overlapHeight: Int,
        totalTopHeight: Int, totalBottomHeight: Int
    ) -> Double {
        let bytesPerRow = width * 4
        var totalDiff: Int = 0
        var sampleCount = 0

        let rowCount = overlapHeight
        let step = 1
        let xMargin = min(20, width / 10) * 4

        for i in 0..<rowCount {
            let offset = i * step
            let topRow = topStartRow + offset
            let bottomRow = bottomStartRow + offset

            guard topRow >= 0, topRow < totalTopHeight,
                  bottomRow >= 0, bottomRow < totalBottomHeight else { continue }

            let topOffset = topRow * bytesPerRow
            let bottomOffset = bottomRow * bytesPerRow

            guard topOffset + bytesPerRow <= topData.count,
                  bottomOffset + bytesPerRow <= bottomData.count else { continue }

            for x in stride(from: xMargin, to: bytesPerRow - xMargin, by: 16) {
                totalDiff += abs(Int(topData[topOffset + x]) - Int(bottomData[bottomOffset + x]))
                totalDiff += abs(Int(topData[topOffset + x + 1]) - Int(bottomData[bottomOffset + x + 1]))
                totalDiff += abs(Int(topData[topOffset + x + 2]) - Int(bottomData[bottomOffset + x + 2]))
                sampleCount += 3
            }
        }

        return sampleCount > 0 ? Double(totalDiff) / Double(sampleCount) : Double.infinity
    }

    // MARK: - Accumulated Image Matching

    /// Find where the new frame's top aligns within the accumulated thumbnail.
    ///
    /// Returns (matchY, newContentRows, score):
    ///   - matchY: row in accumulated where new frame's top aligns (-1 if no match)
    ///   - newContentRows: rows of new frame extending beyond accumulated bottom
    ///   - score: pixel comparison score
    private static func findPositionInAccumulated(
        accumulated: CGImage, newFrame: CGImage
    ) -> (matchY: Int, newContentRows: Int, score: Double) {
        guard accumulated.width == newFrame.width else { return (-1, 0, .infinity) }
        guard let accData = pixelData(for: accumulated),
              let newData = pixelData(for: newFrame) else { return (-1, 0, .infinity) }

        let width = accumulated.width
        let accHeight = accumulated.height
        let frameHeight = newFrame.height

        let minOverlap = max(2, frameHeight * 20 / 100)
        let bytesPerRow = width * 4
        let xMargin = min(20, width / 10) * 4

        // Search range for matchY (where new frame's top row aligns in accumulated)
        let searchMin = max(0, accHeight - frameHeight * 2)
        let searchMax = accHeight - minOverlap

        guard searchMin <= searchMax else { return (-1, 0, .infinity) }

        // Step 1: Compute row profiles
        let accProfile = rowProfile(data: accData, height: accHeight, bytesPerRow: bytesPerRow, xMargin: xMargin)
        let newProfile = rowProfile(data: newData, height: frameHeight, bytesPerRow: bytesPerRow, xMargin: xMargin)

        // Step 2: 1D cross-correlation to find candidate positions
        var candidates = [(matchY: Int, profileScore: Double)]()
        candidates.reserveCapacity(searchMax - searchMin + 1)

        for matchY in searchMin...searchMax {
            let compareLen = min(frameHeight, accHeight - matchY)
            var sumSqDiff: Double = 0
            for r in 0..<compareLen {
                let d = accProfile[matchY + r] - newProfile[r]
                sumSqDiff += d * d
            }
            let profileScore = sqrt(sumSqDiff / Double(compareLen))
            candidates.append((matchY, profileScore))
        }

        // Step 3: Pick top N candidates with ±1 neighbors
        candidates.sort { $0.profileScore < $1.profileScore }
        let topN = min(5, candidates.count)
        var verifySet = Set<Int>()
        for i in 0..<topN {
            let y = candidates[i].matchY
            verifySet.insert(y)
            if y > searchMin { verifySet.insert(y - 1) }
            if y < searchMax { verifySet.insert(y + 1) }
        }

        // Step 4: Full pixel verification on candidates
        var bestMatchY = -1
        var bestScore = Double.infinity

        for matchY in verifySet {
            let compareLen = min(frameHeight, accHeight - matchY)
            let score = compareRows(
                topData: accData, topStartRow: matchY,
                bottomData: newData, bottomStartRow: 0,
                width: width, overlapHeight: compareLen,
                totalTopHeight: accHeight, totalBottomHeight: frameHeight
            )
            if score < bestScore {
                bestScore = score
                bestMatchY = matchY
            }
        }

        if bestScore <= 35.0 && bestMatchY >= 0 {
            let newContentRows = max(0, bestMatchY + frameHeight - accHeight)
            return (bestMatchY, newContentRows, bestScore)
        }

        return (-1, 0, bestScore)
    }

    /// Extend the accumulated thumbnail by appending new content rows from the new frame.
    private static func extendAccumulated(
        _ accumulated: CGImage, with newFrame: CGImage, newContentRows: Int
    ) -> CGImage? {
        guard newContentRows > 0 else { return accumulated }
        let width = accumulated.width
        let newHeight = accumulated.height + newContentRows

        guard let ctx = CGContext(
            data: nil, width: width, height: newHeight,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Draw accumulated at top (CG coords: y = newContentRows since CG origin is bottom-left)
        ctx.draw(accumulated, in: CGRect(x: 0, y: newContentRows, width: width, height: accumulated.height))

        // Crop bottom newContentRows from newFrame
        // In CGImage pixel coords (top-left origin), bottom rows start at y = height - newContentRows
        let cropRect = CGRect(x: 0, y: newFrame.height - newContentRows, width: newFrame.width, height: newContentRows)
        if let croppedNew = newFrame.cropping(to: cropRect) {
            ctx.draw(croppedNew, in: CGRect(x: 0, y: 0, width: width, height: newContentRows))
        }

        return ctx.makeImage()
    }

    /// Crop the bottom N rows from an image.
    private static func cropBottom(_ image: CGImage, rows: Int) -> CGImage? {
        let cropRows = min(rows, image.height)
        // CGImage pixel coords: top-left origin, so bottom rows start at y = height - rows
        return image.cropping(to: CGRect(x: 0, y: image.height - cropRows, width: image.width, height: cropRows))
    }

    // MARK: - Image Utilities

    private static func downscale(_ image: CGImage, by factor: Int) -> CGImage? {
        let newWidth = max(1, image.width / factor)
        let newHeight = max(1, image.height / factor)

        guard let ctx = CGContext(
            data: nil, width: newWidth, height: newHeight,
            bitsPerComponent: 8, bytesPerRow: newWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return ctx.makeImage()
    }

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

    // MARK: - Debug Save

    /// Save all frames and stitching result to a debug folder, then open in Finder.
    static func saveDebug(frames: [CGImage], result: CGImage?, debug: StitchDebugInfo, to baseDir: String) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: baseDir, withIntermediateDirectories: true)

        // Save each frame
        for (i, frame) in frames.enumerated() {
            let path = "\(baseDir)/frame-\(String(format: "%03d", i)).png"
            savePNG(frame, to: path)
        }

        // Save result
        if let result {
            savePNG(result, to: "\(baseDir)/result.png")
        }

        // Save log
        let logPath = "\(baseDir)/stitch-log.txt"
        try? debug.log.write(toFile: logPath, atomically: true, encoding: .utf8)
    }

    private static func savePNG(_ image: CGImage, to path: String) {
        guard let dest = CGImageDestinationCreateWithURL(
            URL(fileURLWithPath: path) as CFURL,
            "public.png" as CFString, 1, nil
        ) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
