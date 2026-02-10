import AppKit

protocol SelectionViewDelegate: AnyObject {
    func selectionDidComplete(rect: CGRect)
    func selectionDidCancel()
}

final class SelectionView: NSView {
    weak var delegate: SelectionViewDelegate?

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var selectionRect: CGRect? {
        guard let start = startPoint, let current = currentPoint else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        guard let rect = selectionRect, rect.width > 5, rect.height > 5 else {
            delegate?.selectionDidCancel()
            return
        }
        // Convert view coordinates to screen coordinates
        guard let windowFrame = window?.frame else { return }
        let screenRect = CGRect(
            x: windowFrame.origin.x + rect.origin.x,
            y: windowFrame.origin.y + rect.origin.y,
            width: rect.width,
            height: rect.height
        )
        delegate?.selectionDidComplete(rect: screenRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            delegate?.selectionDidCancel()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw dark overlay
        NSColor.black.withAlphaComponent(0.3).setFill()
        if let sel = selectionRect {
            // Draw overlay with a transparent hole for the selection
            let fullPath = NSBezierPath(rect: bounds)
            fullPath.windingRule = .evenOdd
            fullPath.append(NSBezierPath(rect: sel))
            fullPath.fill()

            // Draw selection border
            NSColor.systemBlue.setStroke()
            let borderPath = NSBezierPath(rect: sel)
            borderPath.lineWidth = 1.5
            borderPath.stroke()

            // Draw corner and edge handles
            drawHandles(for: sel)

            // Draw dimension label
            drawDimensionLabel(for: sel)
        } else {
            // No selection yet — full dark overlay
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

    private func drawDimensionLabel(for rect: CGRect) {
        let text = "\(Int(rect.width)) \u{00D7} \(Int(rect.height)) pt"
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
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: bgRect, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(
            at: CGPoint(x: bgRect.origin.x + padding, y: bgRect.origin.y + padding / 2),
            withAttributes: attrs
        )
    }
}
