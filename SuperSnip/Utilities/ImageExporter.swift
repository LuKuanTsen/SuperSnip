import AppKit
import UniformTypeIdentifiers

final class ImageExporter {
    /// Show save panel as a sheet on the given window (standard macOS pattern for floating panels).
    static func saveAsSheet(_ image: CGImage, from window: NSWindow, completion: @escaping () -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = defaultFilename()
        panel.canCreateDirectories = true

        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else {
                completion()
                return
            }

            let isPNG = url.pathExtension.lowercased() == "png"
            guard let dest = CGImageDestinationCreateWithURL(
                url as CFURL,
                (isPNG ? UTType.png.identifier : UTType.jpeg.identifier) as CFString,
                1, nil
            ) else {
                completion()
                return
            }

            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
            completion()
        }
    }

    /// Show GIF save panel as a sheet on the given window.
    static func saveGifAsSheet(_ data: Data, from window: NSWindow, completion: @escaping () -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.gif]
        panel.nameFieldStringValue = defaultFilename(extension: "gif")
        panel.canCreateDirectories = true

        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else {
                completion()
                return
            }

            try? data.write(to: url)
            completion()
        }
    }

    private static func defaultFilename(extension ext: String = "png") -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withFullTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        return "screenshot-\(timestamp).\(ext)"
    }
}
