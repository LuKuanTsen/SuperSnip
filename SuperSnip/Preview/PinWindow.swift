import AppKit
import SwiftUI

enum PinAction {
    case copy
    case save
    case edit
    case close
}

final class PinWindow: NSPanel {
    let pinnedImage: CGImage
    var onAction: ((PinAction, PinWindow) -> Void)?

    private var toolbarWindow: NSPanel?
    private var hideTimer: Timer?
    private var isMouseInside = false
    private var isMouseInToolbar = false
    private let resizeHandleSize: CGFloat = 20
    private var resizeGripView: ResizeGripView!

    init(image: CGImage, frame rect: CGRect) {
        self.pinnedImage = image

        super.init(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.minSize = NSSize(width: 50, height: 50)
        // Do NOT set contentAspectRatio — it conflicts with manual resize anchoring
        // and causes the window to jump. We handle aspect ratio ourselves in performResize.

        let nsImage = NSImage(cgImage: image, size: NSSize(width: rect.width, height: rect.height))

        let container = PinContentView(frame: NSRect(origin: .zero, size: rect.size))
        container.wantsLayer = true
        container.layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.5).cgColor
        container.layer?.borderWidth = 1
        container.layer?.cornerRadius = 2
        container.pinWindow = self

        let imageView = DraggableImageView(frame: container.bounds)
        imageView.image = nsImage
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        container.addSubview(imageView)

        // Resize grip drawn on top of everything
        resizeGripView = ResizeGripView(
            frame: NSRect(x: rect.width - resizeHandleSize, y: 0, width: resizeHandleSize, height: resizeHandleSize)
        )
        resizeGripView.autoresizingMask = [.minXMargin, .maxYMargin]
        resizeGripView.isHidden = true
        container.addSubview(resizeGripView)

        self.contentView = container

        // Track mouse for showing/hiding toolbar
        let trackingArea = NSTrackingArea(
            rect: container.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        container.addTrackingArea(trackingArea)
    }

    override var canBecomeKey: Bool { true }

    // Allow dragging beyond screen edges (macOS normally clamps to menu bar)
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            onAction?(.close, self)
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: - Hover tracking

    override func mouseEntered(with event: NSEvent) {
        isMouseInside = true
        hideTimer?.invalidate()
        hideTimer = nil
        showHoverUI()
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInside = false
        scheduleHideHoverUI()
    }

    func toolbarMouseEntered() {
        isMouseInToolbar = true
        hideTimer?.invalidate()
        hideTimer = nil
    }

    func toolbarMouseExited() {
        isMouseInToolbar = false
        scheduleHideHoverUI()
    }

    private func scheduleHideHoverUI() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            guard let self, !self.isMouseInside, !self.isMouseInToolbar else { return }
            self.hideHoverUI()
        }
    }

    private func showHoverUI() {
        resizeGripView.isHidden = false
        showToolbar()
    }

    private func hideHoverUI() {
        resizeGripView.isHidden = true
        hideToolbar()
    }

    // MARK: - Resize (called from PinContentView.mouseDown)

    func isInResizeHandle(_ locationInWindow: CGPoint) -> Bool {
        guard let contentView else { return false }
        let point = contentView.convert(locationInWindow, from: nil)
        let handleRect = CGRect(
            x: contentView.bounds.maxX - resizeHandleSize,
            y: 0,
            width: resizeHandleSize,
            height: resizeHandleSize
        )
        return handleRect.contains(point)
    }

    /// Runs a synchronous drag loop for smooth resize. Anchors at top-left (visual).
    func performResize(with initialEvent: NSEvent) {
        let startMouse = NSEvent.mouseLocation
        let startFrame = self.frame
        // In AppKit coords, top-left visual = (origin.x, origin.y + height)
        let anchorTopLeft = CGPoint(x: startFrame.origin.x, y: startFrame.maxY)
        let aspect = startFrame.height / startFrame.width

        // Hide toolbar during resize to avoid it lagging behind
        hideToolbar()

        // Synchronous event tracking loop — smoothest possible resize
        var keepRunning = true
        while keepRunning {
            guard let event = self.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { continue }
            switch event.type {
            case .leftMouseDragged:
                let currentMouse = NSEvent.mouseLocation
                let deltaX = currentMouse.x - startMouse.x
                let newWidth = max(minSize.width, startFrame.width + deltaX)
                let newHeight = newWidth * aspect

                // Anchor at top-left: origin.y = anchorTopLeft.y - newHeight
                let newFrame = NSRect(
                    x: anchorTopLeft.x,
                    y: anchorTopLeft.y - newHeight,
                    width: newWidth,
                    height: newHeight
                )
                setFrame(newFrame, display: true)

            case .leftMouseUp:
                keepRunning = false

            default:
                break
            }
        }

        // Re-show toolbar after resize
        if isMouseInside {
            showToolbar()
        }
    }

    // MARK: - Toolbar

    private func showToolbar() {
        guard toolbarWindow == nil else { return }

        let toolbar = PinToolbar { [weak self] action in
            guard let self else { return }
            self.onAction?(action, self)
        }
        let hostingView = NSHostingView(rootView: toolbar)
        hostingView.frame.size = hostingView.fittingSize

        let myFrame = self.frame
        let toolbarRect = CGRect(
            x: myFrame.midX - hostingView.frame.width / 2,
            y: myFrame.origin.y - hostingView.frame.height - 6,
            width: hostingView.frame.width,
            height: hostingView.frame.height
        )

        let toolbarPanel = PinToolbarPanel(
            contentRect: toolbarRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        toolbarPanel.level = .floating
        toolbarPanel.isOpaque = false
        toolbarPanel.backgroundColor = .clear
        toolbarPanel.contentView = hostingView
        toolbarPanel.parentPinWindow = self

        let trackingArea = NSTrackingArea(
            rect: NSRect(origin: .zero, size: toolbarRect.size),
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: toolbarPanel,
            userInfo: nil
        )
        hostingView.addTrackingArea(trackingArea)

        self.addChildWindow(toolbarPanel, ordered: .above)
        self.toolbarWindow = toolbarPanel
    }

    private func hideToolbar() {
        if let tw = toolbarWindow {
            self.removeChildWindow(tw)
            tw.orderOut(nil)
            toolbarWindow = nil
        }
    }

    func dismiss() {
        hideTimer?.invalidate()
        hideToolbar()
        self.orderOut(nil)
    }
}

// MARK: - Pin Content View

final class PinContentView: NSView {
    weak var pinWindow: PinWindow?
    private var dragStartMouse: CGPoint?
    private var dragStartOrigin: CGPoint?

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        guard let pinWindow else {
            super.mouseDown(with: event)
            return
        }
        if pinWindow.isInResizeHandle(event.locationInWindow) {
            pinWindow.performResize(with: event)
        } else {
            // Record initial positions — compute absolute offset each frame to avoid drift
            dragStartMouse = NSEvent.mouseLocation
            dragStartOrigin = pinWindow.frame.origin
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let pinWindow,
              let startMouse = dragStartMouse,
              let startOrigin = dragStartOrigin else { return }
        let current = NSEvent.mouseLocation
        let newOrigin = CGPoint(
            x: startOrigin.x + (current.x - startMouse.x),
            y: startOrigin.y + (current.y - startMouse.y)
        )
        pinWindow.setFrameOrigin(newOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        dragStartMouse = nil
        dragStartOrigin = nil
    }
}

// MARK: - Resize Grip View (drawn on top of image)

final class ResizeGripView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Semi-transparent background for visibility
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.3).cgColor)
        let bgPath = CGMutablePath()
        bgPath.move(to: CGPoint(x: bounds.maxX, y: bounds.minY))
        bgPath.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY))
        bgPath.addLine(to: CGPoint(x: bounds.minX, y: bounds.minY))
        bgPath.closeSubpath()
        ctx.addPath(bgPath)
        ctx.fillPath()

        // Draw three diagonal grip lines
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(1)
        let offsets: [CGFloat] = [5, 10, 15]
        for offset in offsets {
            ctx.move(to: CGPoint(x: bounds.maxX - offset, y: bounds.minY + 1))
            ctx.addLine(to: CGPoint(x: bounds.maxX - 1, y: bounds.minY + offset))
            ctx.strokePath()
        }
    }

    // Forward mouse events to the content view for resize handling
    override func mouseDown(with event: NSEvent) {
        nextResponder?.mouseDown(with: event)
    }
}

// MARK: - Draggable Image View

final class DraggableImageView: NSImageView {
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        nextResponder?.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        nextResponder?.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        nextResponder?.mouseUp(with: event)
    }
}

// MARK: - Toolbar Panel

final class PinToolbarPanel: NSPanel {
    weak var parentPinWindow: PinWindow?

    override func mouseEntered(with event: NSEvent) {
        parentPinWindow?.toolbarMouseEntered()
    }

    override func mouseExited(with event: NSEvent) {
        parentPinWindow?.toolbarMouseExited()
    }
}

// MARK: - Pin Toolbar (SwiftUI)

struct PinToolbar: View {
    let onAction: (PinAction) -> Void

    var body: some View {
        HStack(spacing: 2) {
            pinButton(icon: "doc.on.doc", tooltip: "Copy", action: .copy)
            pinButton(icon: "square.and.arrow.down", tooltip: "Save", action: .save)

            Divider().frame(height: 20)

            pinButton(icon: "pencil.and.outline", tooltip: "Edit", action: .edit)

            Divider().frame(height: 20)

            pinButton(icon: "xmark", tooltip: "Close", action: .close)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func pinButton(icon: String, tooltip: String, action: PinAction) -> some View {
        Button {
            onAction(action)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}
