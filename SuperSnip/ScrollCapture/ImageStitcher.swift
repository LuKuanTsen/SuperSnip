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

    /// Stitch frames and return debug info alongside the result.
    static func stitchWithDebug(frames: [CGImage]) -> (image: CGImage?, debug: StitchDebugInfo) {
        let emptyDebug = StitchDebugInfo(pairs: [], validIndices: [0], validOverlaps: [], frameCount: frames.count)
        guard !frames.isEmpty else { return (nil, emptyDebug) }
        guard frames.count >= 2 else { return (frames.first, emptyDebug) }

        // Step 1: Create thumbnails
        let thumbs = frames.map { downscale($0, by: scaleFactor) }

        // Step 2: Find overlaps, collect debug info
        // Skip frames with no valid overlap (instead of concatenating, which duplicates content).
        // The next frame will be compared against the last valid frame.
        var validIndices = [0]
        var validOverlaps = [Int]()
        var lastValidIdx = 0
        var pairInfos = [StitchDebugInfo.PairInfo]()
        var consecutiveSkips = 0
        let maxConsecutiveSkips = 3

        for i in 1..<frames.count {
            guard let top = thumbs[lastValidIdx],
                  let bottom = thumbs[i] else {
                pairInfos.append(.init(
                    frameIndex: i, comparedAgainst: lastValidIdx,
                    thumbOverlap: 0, fullOverlap: 0, bestScore: .infinity,
                    decision: "skipped (thumbnail failed)"
                ))
                consecutiveSkips += 1
                continue
            }

            let (thumbOverlap, bestScore) = findOverlapWithScore(top: top, bottom: bottom)
            let fullOverlap = thumbOverlap * scaleFactor

            // Skip frames with no overlap found (likely reverse scroll or content change).
            // The next frame will be compared against the last valid frame instead.
            if thumbOverlap == 0 {
                if consecutiveSkips < maxConsecutiveSkips {
                    pairInfos.append(.init(
                        frameIndex: i, comparedAgainst: lastValidIdx,
                        thumbOverlap: 0, fullOverlap: 0, bestScore: bestScore,
                        decision: "skipped (no overlap, will retry next frame against \(lastValidIdx))"
                    ))
                    consecutiveSkips += 1
                    continue
                } else {
                    // Too many consecutive skips — force-keep to avoid losing content
                    pairInfos.append(.init(
                        frameIndex: i, comparedAgainst: lastValidIdx,
                        thumbOverlap: 0, fullOverlap: 0, bestScore: bestScore,
                        decision: "force-kept (no overlap, \(consecutiveSkips) consecutive skips)"
                    ))
                }
            } else {
                let pct = fullOverlap * 100 / frames[i].height
                pairInfos.append(.init(
                    frameIndex: i, comparedAgainst: lastValidIdx,
                    thumbOverlap: thumbOverlap, fullOverlap: fullOverlap, bestScore: bestScore,
                    decision: "kept (overlap \(pct)%)"
                ))
            }

            consecutiveSkips = 0
            validIndices.append(i)
            validOverlaps.append(fullOverlap)
            lastValidIdx = i
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
