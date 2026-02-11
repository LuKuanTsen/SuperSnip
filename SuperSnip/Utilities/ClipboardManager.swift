import AppKit

final class ClipboardManager {
    static func copyToClipboard(_ image: CGImage) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let nsImage = NSImage(
            cgImage: image,
            size: NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        )
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([nsImage])
    }
}
