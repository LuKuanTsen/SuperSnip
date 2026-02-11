import AppKit

protocol SelectionViewDelegate: AnyObject {
    func selectionDidComplete(rect: CGRect)
    func selectionDidCancel()
}

/// Coordinates selection state across multiple overlay windows (one per screen).
/// All coordinates are in global screen coordinates (AppKit: origin at bottom-left of main screen).
final class SelectionCoordinator {
    weak var delegate: SelectionViewDelegate?
    var views: [SelectionView] = []

    private var startPoint: CGPoint?  // screen coordinates
    private var currentPoint: CGPoint?  // screen coordinates

    var selectionRect: CGRect? {
        guard let start = startPoint, let current = currentPoint else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    func mouseDown(screenPoint: CGPoint) {
        startPoint = screenPoint
        currentPoint = screenPoint
        redrawAll()
    }

    func mouseDragged(screenPoint: CGPoint) {
        currentPoint = screenPoint
        redrawAll()
    }

    func mouseUp(screenPoint: CGPoint) {
        currentPoint = screenPoint
        guard let rect = selectionRect, rect.width > 5, rect.height > 5 else {
            delegate?.selectionDidCancel()
            return
        }
        delegate?.selectionDidComplete(rect: rect)
    }

    func cancel() {
        delegate?.selectionDidCancel()
    }

    private func redrawAll() {
        for view in views {
            view.needsDisplay = true
        }
    }
}

final class SelectionView: NSView {
    weak var coordinator: SelectionCoordinator?

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: - Mouse Events (convert to screen coordinates)

    private func screenPoint(for event: NSEvent) -> CGPoint {
        let windowPoint = event.locationInWindow
        return window?.convertPoint(toScreen: windowPoint) ?? windowPoint
    }

    override func mouseDown(with event: NSEvent) {
        coordinator?.mouseDown(screenPoint: screenPoint(for: event))
    }

    override func mouseDragged(with event: NSEvent) {
        coordinator?.mouseDragged(screenPoint: screenPoint(for: event))
    }

    override func mouseUp(with event: NSEvent) {
        coordinator?.mouseUp(screenPoint: screenPoint(for: event))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            coordinator?.cancel()
        }
    }

    // MARK: - Drawing

    /// Convert a rect from screen coordinates to this view's local coordinates.
    private func localRect(from screenRect: CGRect) -> CGRect {
        guard let window = self.window else { return screenRect }
        let windowRect = window.convertFromScreen(screenRect)
        return convert(windowRect, from: nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.black.withAlphaComponent(0.3).setFill()

        if let globalSel = coordinator?.selectionRect {
            let sel = localRect(from: globalSel)

            // Draw overlay with a transparent hole for the selection
            let fullPath = NSBezierPath(rect: bounds)
            fullPath.windingRule = .evenOdd
            let visibleSel = sel.intersection(bounds)
            if !visibleSel.isNull {
                fullPath.append(NSBezierPath(rect: visibleSel))
            }
            fullPath.fill()

            // Draw selection border (clipped to this view)
            NSColor.systemBlue.setStroke()
            let borderPath = NSBezierPath(rect: sel)
            borderPath.lineWidth = 1.5
            borderPath.stroke()

            // Draw handles and label
            drawHandles(for: sel)
            drawDimensionLabel(for: sel, globalRect: globalSel)
        } else {
            NSBezierPath(rect: bounds).fill()
        }
    }

    private func drawHandles(for rect: CGRect) {
        let handleSize: CGFloat = 6
        let points = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.midY),
            CGPoint(x: rect.maxX, y: rect.midY),
        ]

        for point in points {
            // Only draw if this handle is within or near our bounds
            guard bounds.insetBy(dx: -handleSize, dy: -handleSize).contains(point) else { continue }

            let handleRect = CGRect(
                x: point.x - handleSize / 2,
                y: point.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            NSColor.white.setFill()
            let handle = NSBezierPath(ovalIn: handleRect)
            handle.fill()
            NSColor.systemBlue.setStroke()
            handle.lineWidth = 1
            handle.stroke()
        }
    }

    private func drawDimensionLabel(for rect: CGRect, globalRect: CGRect) {
        // Use global rect dimensions for the label text
        let text = "\(Int(globalRect.width)) \u{00D7} \(Int(globalRect.height)) pt"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let padding: CGFloat = 6
        let bgRect = CGRect(
            x: rect.origin.x,
            y: rect.maxY + 4,
            width: size.width + padding * 2,
            height: size.height + padding
        )

        // Only draw if the label is visible on this screen
        guard bounds.intersects(bgRect) else { return }

        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: bgRect, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(
            at: CGPoint(x: bgRect.origin.x + padding, y: bgRect.origin.y + padding / 2),
            withAttributes: attrs
        )
    }
}
