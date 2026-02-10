import AppKit
import CoreGraphics

final class ScreenCaptureManager {
    /// Capture a screen region.
    /// `rect` is in AppKit screen coordinates (origin at bottom-left of primary display).
    static func capture(rect: CGRect) -> CGImage? {
        // Convert AppKit coordinates (origin bottom-left) to CG coordinates (origin top-left)
        guard let mainScreen = NSScreen.screens.first else { return nil }
        let screenHeight = mainScreen.frame.height
        let cgRect = CGRect(
            x: rect.origin.x,
            y: screenHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
        return CGWindowListCreateImage(
            cgRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        )
    }
}
