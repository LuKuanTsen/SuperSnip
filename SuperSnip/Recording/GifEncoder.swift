import AppKit
import ImageIO
import UniformTypeIdentifiers

final class GifEncoder {
    static func encode(frames: [CGImage], frameDelay: Double, to url: URL) -> Bool {
        guard !frames.isEmpty else { return false }
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.gif.identifier as CFString,
            frames.count,
            nil
        ) else { return false }

        setGifProperties(on: dest, frames: frames, frameDelay: frameDelay)
        return CGImageDestinationFinalize(dest)
    }

    static func encodeToData(frames: [CGImage], frameDelay: Double) -> Data? {
        guard !frames.isEmpty else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.gif.identifier as CFString,
            frames.count,
            nil
        ) else { return nil }

        setGifProperties(on: dest, frames: frames, frameDelay: frameDelay)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    private static func setGifProperties(on dest: CGImageDestination, frames: [CGImage], frameDelay: Double) {
        // Loop infinitely
        let gifProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0
            ]
        ]
        CGImageDestinationSetProperties(dest, gifProperties as CFDictionary)

        // Add each frame
        let frameProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: frameDelay
            ]
        ]
        for frame in frames {
            CGImageDestinationAddImage(dest, frame, frameProperties as CFDictionary)
        }
    }
}
