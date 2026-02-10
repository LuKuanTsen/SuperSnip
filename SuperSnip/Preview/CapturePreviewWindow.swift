import AppKit
import SwiftUI

final class CapturePreviewWindow: NSPanel {
    var onAction: ((ToolbarAction) -> Void)?
    private var toolbarWindow: NSPanel?

    init(image: CGImage, screenRect: CGRect) {
        let imageSize = NSSize(width: screenRect.width, height: screenRect.height)

        super.init(
            contentRect: screenRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true

        // Image view
        let nsImage = NSImage(cgImage: image, size: imageSize)
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: imageSize))
        imageView.image = nsImage
        imageView.imageScaling = .scaleAxesIndependently
        self.contentView = imageView

        // Selection border overlay
        let borderView = NSView(frame: NSRect(origin: .zero, size: imageSize))
        borderView.wantsLayer = true
        borderView.layer?.borderColor = NSColor.systemBlue.cgColor
        borderView.layer?.borderWidth = 1.5
        borderView.autoresizingMask = [.width, .height]
        imageView.addSubview(borderView)

        // Toolbar as child window below the image
        setupToolbar(below: screenRect)
    }

    private func setupToolbar(below rect: CGRect) {
        let toolbarView = ActionToolbar { [weak self] action in
            self?.onAction?(action)
        }
        let hostingView = NSHostingView(rootView: toolbarView)
        hostingView.frame.size = hostingView.fittingSize

        let toolbarRect = CGRect(
            x: rect.midX - hostingView.frame.width / 2,
            y: rect.origin.y - hostingView.frame.height - 8,
            width: hostingView.frame.width,
            height: hostingView.frame.height
        )

        let toolbar = NSPanel(
            contentRect: toolbarRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        toolbar.level = .floating
        toolbar.isOpaque = false
        toolbar.backgroundColor = .clear
        toolbar.contentView = hostingView

        self.addChildWindow(toolbar, ordered: .above)
        self.toolbarWindow = toolbar
    }

    override var canBecomeKey: Bool { true }

    /// Handle ESC to dismiss
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onAction?(.cancel)
        } else {
            super.keyDown(with: event)
        }
    }

    func dismiss() {
        toolbarWindow?.orderOut(nil)
        toolbarWindow = nil
        self.orderOut(nil)
    }
}
