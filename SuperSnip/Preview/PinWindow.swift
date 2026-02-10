import AppKit

final class PinWindow: NSPanel {
    private let closeButton: NSButton

    init(image: CGImage, frame rect: CGRect) {
        let nsImage = NSImage(cgImage: image, size: NSSize(width: rect.width, height: rect.height))

        closeButton = NSButton(
            image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")!,
            target: nil,
            action: nil
        )
        closeButton.isBordered = false
        closeButton.isHidden = true

        super.init(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let container = NSView(frame: NSRect(origin: .zero, size: rect.size))

        let imageView = NSImageView(frame: container.bounds)
        imageView.image = nsImage
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        container.addSubview(imageView)

        // Border
        container.wantsLayer = true
        container.layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.5).cgColor
        container.layer?.borderWidth = 1
        container.layer?.cornerRadius = 2

        closeButton.frame = NSRect(x: rect.width - 24, y: rect.height - 24, width: 20, height: 20)
        closeButton.autoresizingMask = [.minXMargin, .minYMargin]
        closeButton.target = self
        closeButton.action = #selector(closePinWindow)
        container.addSubview(closeButton)

        self.contentView = container

        // Track mouse enter/exit for close button visibility
        let trackingArea = NSTrackingArea(
            rect: container.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        container.addTrackingArea(trackingArea)
    }

    override var canBecomeKey: Bool { true }

    override func mouseEntered(with event: NSEvent) {
        closeButton.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        closeButton.isHidden = true
    }

    @objc private func closePinWindow() {
        self.orderOut(nil)
    }
}
