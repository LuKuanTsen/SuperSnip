import AppKit
import CoreGraphics

final class ScreenCaptureManager {
    /// Capture a screen region.
    /// `rect` is in AppKit screen coordinates (origin at bottom-left of primary display).
    static func capture(rect: CGRect, includeCursor: Bool = false) -> CGImage? {
        // Convert AppKit coordinates (origin bottom-left) to CG coordinates (origin top-left)
        guard let mainScreen = NSScreen.screens.first else { return nil }
        let screenHeight = mainScreen.frame.height
        let cgRect = CGRect(
            x: rect.origin.x,
            y: screenHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
        guard let image = CGWindowListCreateImage(
            cgRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else { return nil }

        guard includeCursor else { return image }
        return drawCursor(on: image, captureRect: rect)
    }

    /// Draw the current mouse cursor onto the captured image.
    private static func drawCursor(on image: CGImage, captureRect: CGRect) -> CGImage {
        // Mouse location in AppKit screen coords (bottom-left origin)
        let mouseLocation = NSEvent.mouseLocation
        let cursor = NSCursor.current

        // Cursor hotspot offset (top-left origin in cursor image)
        let hotspot = cursor.hotSpot
        let cursorImage = cursor.image

        // Scale factor: image pixels vs capture rect points
        let scaleX = CGFloat(image.width) / captureRect.width
        let scaleY = CGFloat(image.height) / captureRect.height

        // Cursor draw position in image pixel coords (top-left origin)
        let cursorX = (mouseLocation.x - captureRect.origin.x) * scaleX - hotspot.x * scaleX
        let cursorY = (captureRect.origin.y + captureRect.height - mouseLocation.y) * scaleY - hotspot.y * scaleY
        let cursorW = cursorImage.size.width * scaleX
        let cursorH = cursorImage.size.height * scaleY

        // Check if cursor is within the capture area
        guard cursorX + cursorW > 0, cursorY + cursorH > 0,
              cursorX < CGFloat(image.width), cursorY < CGFloat(image.height) else {
            return image
        }

        guard let ctx = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return image }

        // Draw original image
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        // Draw cursor (CG context is bottom-left origin, so flip Y)
        if let cursorCG = cursorImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let drawY = CGFloat(image.height) - cursorY - cursorH
            ctx.draw(cursorCG, in: CGRect(x: cursorX, y: drawY, width: cursorW, height: cursorH))
        }

        return ctx.makeImage() ?? image
    }
}
