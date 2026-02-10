import AppKit
import UniformTypeIdentifiers

final class ImageExporter {
    static func saveWithDialog(_ image: CGImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = "screenshot.png"
        panel.canCreateDirectories = true

        // LSUIElement apps lose focus easily, causing the save panel to dismiss.
        // Temporarily become a regular app so the panel stays interactive.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let response = panel.runModal()

        // Switch back to accessory (menu bar only, no Dock icon)
        NSApp.setActivationPolicy(.accessory)

        guard response == .OK, let url = panel.url else { return }

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
