import AppKit

struct Stroke {
    var points: [CGPoint]
    let color: NSColor
    let width: CGFloat
    let mode: CanvasEditMode
    /// Random grid offset (0..<1) for mosaic — each stroke gets a different grid alignment
    let gridOffset: CGPoint

    init(points: [CGPoint], color: NSColor, width: CGFloat, mode: CanvasEditMode) {
        self.points = points
        self.color = color
        self.width = width
        self.mode = mode
        self.gridOffset = mode == .mosaic
            ? CGPoint(x: CGFloat.random(in: 0..<1), y: CGFloat.random(in: 0..<1))
            : .zero
    }
}

final class EditingCanvasView: NSView {
    var originalImage: CGImage
    var editMode: CanvasEditMode = .draw
    var brushSize: BrushSize = .medium
    var drawColor: NSColor = .systemRed

    private(set) var strokes: [Stroke] = []
    private var currentStroke: Stroke?
    private var mouseLocation: CGPoint?
    private var trackingArea: NSTrackingArea?

    init(image: CGImage, frame: NSRect, existingStrokes: [Stroke] = []) {
        self.originalImage = image
        self.strokes = existingStrokes
        super.init(frame: frame)
        updateTrackingArea()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // MARK: - Tracking Area

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        updateTrackingArea()
    }

    private func updateTrackingArea() {
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    // MARK: - Public API

    func undo() {
        guard !strokes.isEmpty else { return }
        strokes.removeLast()
        needsDisplay = true
    }

    var hasStrokes: Bool { !strokes.isEmpty }

    func compositeResult() -> CGImage? {
        compositeImage(strokes: strokes)
    }

    /// Composite an arbitrary set of strokes onto the original image (used for undo/redo outside editing)
    func compositeImage(strokes: [Stroke]) -> CGImage? {
        let imageWidth = originalImage.width
        let imageHeight = originalImage.height

        guard let context = CGContext(
            data: nil,
            width: imageWidth,
            height: imageHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        let fullRect = CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)
        context.draw(originalImage, in: fullRect)

        let scaleX = CGFloat(imageWidth) / bounds.width
        let scaleY = CGFloat(imageHeight) / bounds.height

        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext

        for stroke in strokes {
            guard stroke.points.count >= 2 else { continue }

            if stroke.mode == .draw {
                renderDrawStroke(stroke, scaleX: scaleX, scaleY: scaleY)
            } else {
                renderMosaicStrokeToContext(stroke, context: context, scaleX: scaleX, scaleY: scaleY)
            }
        }

        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    // MARK: - Mouse Handling

    override func mouseEntered(with event: NSEvent) {
        mouseLocation = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        mouseLocation = nil
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        mouseLocation = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        currentStroke = Stroke(
            points: [point],
            color: drawColor,
            width: brushSize.rawValue,
            mode: editMode
        )
        mouseLocation = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        mouseLocation = point

        guard currentStroke != nil else { return }

        if let lastPoint = currentStroke?.points.last {
            let interpolated = interpolatePoints(from: lastPoint, to: point, maxSpacing: brushSize.rawValue * 0.3)
            currentStroke?.points.append(contentsOf: interpolated)
        }
        currentStroke?.points.append(point)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let stroke = currentStroke {
            strokes.append(stroke)
        }
        currentStroke = nil
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.draw(originalImage, in: bounds)
        ctx.restoreGState()

        // Render finalized mosaic strokes
        renderAllMosaicStrokes()

        // Render finalized draw strokes
        for stroke in strokes where stroke.mode == .draw {
            drawBezierStroke(stroke)
        }

        // Render current in-progress stroke
        if let current = currentStroke {
            if current.mode == .draw {
                drawBezierStroke(current)
            } else {
                renderMosaicStrokePreview(current)
            }
        }

        // Brush preview circle
        if let loc = mouseLocation {
            let radius = brushSize.rawValue / 2
            let previewRect = CGRect(
                x: loc.x - radius,
                y: loc.y - radius,
                width: brushSize.rawValue,
                height: brushSize.rawValue
            )
            let circle = NSBezierPath(ovalIn: previewRect)
            circle.lineWidth = 1.0
            NSColor.white.withAlphaComponent(0.8).setStroke()
            circle.stroke()
            let inner = NSBezierPath(ovalIn: previewRect.insetBy(dx: 1, dy: 1))
            inner.lineWidth = 0.5
            NSColor.black.withAlphaComponent(0.4).setStroke()
            inner.stroke()
        }
    }

    // MARK: - Draw Mode Rendering

    private func drawBezierStroke(_ stroke: Stroke) {
        guard stroke.points.count >= 2 else { return }
        let path = NSBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.lineWidth = stroke.width

        path.move(to: stroke.points[0])
        for i in 1..<stroke.points.count {
            path.line(to: stroke.points[i])
        }

        stroke.color.setStroke()
        path.stroke()
    }

    private func renderDrawStroke(_ stroke: Stroke, scaleX: CGFloat, scaleY: CGFloat) {
        guard stroke.points.count >= 2 else { return }
        let path = NSBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.lineWidth = stroke.width * max(scaleX, scaleY)

        let scaled = stroke.points.map {
            CGPoint(x: $0.x * scaleX, y: $0.y * scaleY)
        }
        path.move(to: scaled[0])
        for i in 1..<scaled.count {
            path.line(to: scaled[i])
        }

        stroke.color.setStroke()
        path.stroke()
    }

    // MARK: - Mosaic Mode Rendering

    private func renderAllMosaicStrokes() {
        let mosaicStrokes = strokes.filter { $0.mode == .mosaic }
        guard !mosaicStrokes.isEmpty else { return }

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let scaleX = CGFloat(originalImage.width) / bounds.width
        let scaleY = CGFloat(originalImage.height) / bounds.height

        for stroke in mosaicStrokes {
            renderMosaicStrokeOnScreen(stroke, context: ctx, scaleX: scaleX, scaleY: scaleY)
        }
    }

    private func renderMosaicStrokePreview(_ stroke: Stroke) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let scaleX = CGFloat(originalImage.width) / bounds.width
        let scaleY = CGFloat(originalImage.height) / bounds.height
        renderMosaicStrokeOnScreen(stroke, context: ctx, scaleX: scaleX, scaleY: scaleY)
    }

    private func renderMosaicStrokeOnScreen(_ stroke: Stroke, context: CGContext, scaleX: CGFloat, scaleY: CGFloat) {
        let blockSize = mosaicBlockSize(for: stroke.width)
        let viewBlockW = blockSize / scaleX
        let viewBlockH = blockSize / scaleY

        // Apply random grid offset for this stroke
        let offsetX = stroke.gridOffset.x * viewBlockW
        let offsetY = stroke.gridOffset.y * viewBlockH

        guard let dataProvider = originalImage.dataProvider,
              let pixelData = dataProvider.data,
              let ptr = CFDataGetBytePtr(pixelData) else { return }

        let bytesPerRow = originalImage.bytesPerRow
        let imgW = originalImage.width
        let imgH = originalImage.height

        var visitedBlocks = Set<Int>()
        let gridCols = Int(ceil(bounds.width / viewBlockW)) + 2

        for point in stroke.points {
            let radius = stroke.width / 2
            let minX = max(0, point.x - radius)
            let maxX = min(bounds.width, point.x + radius)
            let minY = max(0, point.y - radius)
            let maxY = min(bounds.height, point.y + radius)

            let colStart = Int(floor((minX - offsetX) / viewBlockW))
            let colEnd = Int(floor((maxX - offsetX - 0.001) / viewBlockW))
            let rowStart = Int(floor((minY - offsetY) / viewBlockH))
            let rowEnd = Int(floor((maxY - offsetY - 0.001) / viewBlockH))

            for row in rowStart...rowEnd {
                for col in colStart...colEnd {
                    let key = (row + 10000) * gridCols + (col + 10000)
                    guard !visitedBlocks.contains(key) else { continue }
                    visitedBlocks.insert(key)

                    let bx = CGFloat(col) * viewBlockW + offsetX
                    let by = CGFloat(row) * viewBlockH + offsetY

                    // Clip to view bounds
                    let drawX = max(0, bx)
                    let drawY = max(0, by)
                    let drawW = min(bx + viewBlockW, bounds.width) - drawX
                    let drawH = min(by + viewBlockH, bounds.height) - drawY
                    guard drawW > 0, drawH > 0 else { continue }

                    // Map view block center to image pixels for sampling
                    let imgX = Int(bx * scaleX)
                    let imgY = imgH - Int((by + viewBlockH) * scaleY)

                    let avgColor = averageColor(
                        ptr: ptr, bytesPerRow: bytesPerRow,
                        imgW: imgW, imgH: imgH,
                        x: imgX, y: imgY, w: Int(blockSize), h: Int(blockSize)
                    )

                    context.setFillColor(avgColor)
                    context.fill(CGRect(x: drawX, y: drawY, width: drawW, height: drawH))
                }
            }
        }
    }

    private func renderMosaicStrokeToContext(_ stroke: Stroke, context: CGContext, scaleX: CGFloat, scaleY: CGFloat) {
        let blockSize = mosaicBlockSize(for: stroke.width)

        // Apply random grid offset scaled to image pixels
        let offsetX = stroke.gridOffset.x * blockSize
        let offsetY = stroke.gridOffset.y * blockSize

        guard let dataProvider = originalImage.dataProvider,
              let pixelData = dataProvider.data,
              let ptr = CFDataGetBytePtr(pixelData) else { return }

        let bytesPerRow = originalImage.bytesPerRow
        let imgW = originalImage.width
        let imgH = originalImage.height

        var visitedBlocks = Set<Int>()
        let gridCols = Int(ceil(CGFloat(imgW) / blockSize)) + 2

        for point in stroke.points {
            let scaledX = point.x * scaleX
            let scaledY = point.y * scaleY
            let radius = stroke.width * max(scaleX, scaleY) / 2

            let minX = max(0, scaledX - radius)
            let maxX = min(CGFloat(imgW), scaledX + radius)
            let minY = max(0, scaledY - radius)
            let maxY = min(CGFloat(imgH), scaledY + radius)

            let colStart = Int(floor((minX - offsetX) / blockSize))
            let colEnd = Int(floor((maxX - offsetX - 0.001) / blockSize))
            let rowStart = Int(floor((minY - offsetY) / blockSize))
            let rowEnd = Int(floor((maxY - offsetY - 0.001) / blockSize))

            for row in rowStart...rowEnd {
                for col in colStart...colEnd {
                    let key = (row + 10000) * gridCols + (col + 10000)
                    guard !visitedBlocks.contains(key) else { continue }
                    visitedBlocks.insert(key)

                    let bx = CGFloat(col) * blockSize + offsetX
                    let by = CGFloat(row) * blockSize + offsetY

                    // Clip to image bounds
                    let drawX = max(0, bx)
                    let drawY = max(0, by)
                    let drawW = min(bx + blockSize, CGFloat(imgW)) - drawX
                    let drawH = min(by + blockSize, CGFloat(imgH)) - drawY
                    guard drawW > 0, drawH > 0 else { continue }

                    // Flip Y for pixel sampling
                    let sampleY = imgH - Int(by + blockSize)

                    let avgColor = averageColor(
                        ptr: ptr, bytesPerRow: bytesPerRow,
                        imgW: imgW, imgH: imgH,
                        x: Int(bx), y: sampleY, w: Int(blockSize), h: Int(blockSize)
                    )

                    context.setFillColor(avgColor)
                    context.fill(CGRect(x: drawX, y: drawY, width: drawW, height: drawH))
                }
            }
        }
    }

    // MARK: - Helpers

    private func interpolatePoints(from a: CGPoint, to b: CGPoint, maxSpacing: CGFloat) -> [CGPoint] {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let distance = sqrt(dx * dx + dy * dy)
        guard distance > maxSpacing else { return [] }

        let steps = Int(ceil(distance / maxSpacing))
        var result: [CGPoint] = []
        for i in 1..<steps {
            let t = CGFloat(i) / CGFloat(steps)
            result.append(CGPoint(x: a.x + dx * t, y: a.y + dy * t))
        }
        return result
    }

    private func mosaicBlockSize(for brushWidth: CGFloat) -> CGFloat {
        switch brushWidth {
        case BrushSize.small.rawValue: return 10
        case BrushSize.large.rawValue: return 20
        default: return 14
        }
    }

    private func averageColor(
        ptr: UnsafePointer<UInt8>, bytesPerRow: Int,
        imgW: Int, imgH: Int,
        x: Int, y: Int, w: Int, h: Int
    ) -> CGColor {
        let x0 = max(0, min(x, imgW - 1))
        let y0 = max(0, min(y, imgH - 1))
        let x1 = max(0, min(x + w, imgW))
        let y1 = max(0, min(y + h, imgH))

        guard x1 > x0, y1 > y0 else {
            return CGColor(gray: 0.5, alpha: 1)
        }

        var totalR: UInt64 = 0
        var totalG: UInt64 = 0
        var totalB: UInt64 = 0
        var count: UInt64 = 0

        for py in y0..<y1 {
            for px in x0..<x1 {
                let offset = py * bytesPerRow + px * 4
                totalB += UInt64(ptr[offset])
                totalG += UInt64(ptr[offset + 1])
                totalR += UInt64(ptr[offset + 2])
                count += 1
            }
        }

        guard count > 0 else { return CGColor(gray: 0.5, alpha: 1) }

        let r = CGFloat(totalR) / CGFloat(count) / 255.0
        let g = CGFloat(totalG) / CGFloat(count) / 255.0
        let b = CGFloat(totalB) / CGFloat(count) / 255.0
        return CGColor(red: r, green: g, blue: b, alpha: 1)
    }
}
