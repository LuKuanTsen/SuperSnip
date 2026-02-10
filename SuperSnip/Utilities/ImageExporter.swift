import AppKit
import UniformTypeIdentifiers

final class ImageExporter {
    static func saveWithDialog(_ image: CGImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = "screenshot.png"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let isPNG = url.pathExtension.lowercased() == "png"
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL,
            (isPNG ? UTType.png.identifier : UTType.jpeg.identifier) as CFString,
            1, nil
        ) else { return }

        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
