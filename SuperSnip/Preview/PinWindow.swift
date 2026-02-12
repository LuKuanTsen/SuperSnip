import AppKit
import SwiftUI

// MARK: - Enums

enum WindowMode {
    case firstPreview   // Initial capture — shows scroll/GIF/cancel
    case pinned         // From scroll capture result
    case gif            // Animated GIF result
}

enum PinAction {
    case copy
    case save
    case close
    case draw
    case mosaic
    case undo
    case redo
    case scrollCapture
    case scrollCaptureDebug
    case recordGif
}

class EditHistoryState: ObservableObject {
    @Published var canUndo = false
    @Published var canRedo = false
}

// MARK: - PinWindow

final class PinWindow: NSPanel {
    let originalImage: CGImage
    private(set) var currentImage: CGImage
    private(set) var windowMode: WindowMode
    /// For firstPreview: the original screen capture rect (used to start scroll/GIF recording)
    let captureRect: CGRect?

    var gifData: Data? {
        didSet {
            guard let gifData, let container = contentView else { return }
            if let imageView = container.subviews.compactMap({ $0 as? DraggableImageView }).first {
                let gifImage = NSImage(data: gifData)
                imageView.animates = true
                imageView.image = gifImage
            }
        }
    }
    var onAction: ((PinAction, PinWindow) -> Void)?

    // Editing state
    private var accumulatedStrokes: [Stroke] = []
    private var redoStack: [Stroke] = []
    private var lastBrushSize: BrushSize = .medium
    private var lastDrawColor: NSColor = .systemRed
    private let historyState = EditHistoryState()
    private var editingCanvas: EditingCanvasView?
    private var editingToolbarWindow: NSPanel?
    private(set) var isEditing = false

    // Hover / toolbar state
    private var toolbarWindow: NSPanel?
    private var hideTimer: Timer?
    private var isMouseInside = false
    private var isMouseInToolbar = false
    private var toolbarAlwaysVisible: Bool
    private let resizeHandleSize: CGFloat = 20
    private var resizeGripView: ResizeGripView!

    init(image: CGImage, frame rect: CGRect, mode: WindowMode = .pinned, captureRect: CGRect? = nil) {
        self.originalImage = image
        self.currentImage = image
        self.windowMode = mode
        self.captureRect = captureRect
        self.toolbarAlwaysVisible = (mode == .firstPreview)

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
        resizeGripView.isHidden = !toolbarAlwaysVisible
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

        // For firstPreview, show toolbar immediately
        if mode == .firstPreview {
            DispatchQueue.main.async { [weak self] in
                self?.showToolbar()
            }
        }
    }

    override var canBecomeKey: Bool { true }

    // Allow dragging beyond screen edges
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53 { // ESC
            if isEditing {
                exitEditingMode(apply: false)
            } else {
                onAction?(.close, self)
            }
        } else if event.keyCode == 6 && flags.contains(.command) && flags.contains(.shift) {
            // Cmd+Shift+Z — redo (only when not editing)
            if !isEditing {
                performRedo()
            }
        } else if event.keyCode == 6 && flags.contains(.command) {
            // Cmd+Z — undo
            if isEditing {
                editingCanvas?.undo()
            } else {
                performUndo()
            }
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: - Hover tracking

    override func mouseEntered(with event: NSEvent) {
        isMouseInside = true
        hideTimer?.invalidate()
        hideTimer = nil
        if !isEditing {
            showHoverUI()
        }
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInside = false
        if toolbarAlwaysVisible {
            toolbarAlwaysVisible = false
        }
        if !isEditing {
            scheduleHideHoverUI()
        }
    }

    func toolbarMouseEntered() {
        isMouseInToolbar = true
        hideTimer?.invalidate()
        hideTimer = nil
    }

    func toolbarMouseExited() {
        isMouseInToolbar = false
        if !isEditing {
            scheduleHideHoverUI()
        }
    }

    private func scheduleHideHoverUI() {
        guard !toolbarAlwaysVisible else { return }
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

    /// Runs a synchronous drag loop for smooth resize.
    /// Anchor = visible top-left: if window extends above screen, anchors at screen top edge.
    func performResize(with initialEvent: NSEvent) {
        let startMouse = NSEvent.mouseLocation
        let startFrame = self.frame
        let aspect = startFrame.height / startFrame.width

        // Determine anchor Y: clamp to screen's visible top if window extends above it
        let screenTop = NSScreen.screens
            .first(where: { $0.frame.intersects(startFrame) })?
            .visibleFrame.maxY ?? startFrame.maxY
        let anchorY = min(startFrame.maxY, screenTop)
        let anchorX = startFrame.origin.x

        // Hide toolbar during resize to avoid it lagging behind
        hideToolbar()

        // Synchronous event tracking loop — smoothest possible resize
        var keepRunning = true
        while keepRunning {
            guard let event = self.nextEvent(matching: [.leftMouseDragged, .leftMouseUp],
                                             until: .distantFuture, inMode: .eventTracking, dequeue: true)
            else { break }
            switch event.type {
            case .leftMouseDragged:
                let currentMouse = NSEvent.mouseLocation
                let deltaX = currentMouse.x - startMouse.x
                let newWidth = max(minSize.width, startFrame.width + deltaX)
                let newHeight = newWidth * aspect

                let newFrame = NSRect(
                    x: anchorX,
                    y: anchorY - newHeight,
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

    // MARK: - Editing Mode

    func enterEditingMode(mode: CanvasEditMode) {
        guard !isEditing, windowMode != .gif else { return }
        isEditing = true

        // Hide the main toolbar and resize grip
        hideToolbar()
        resizeGripView.isHidden = true

        // Create editing canvas with original image and all accumulated strokes
        let canvasFrame = NSRect(origin: .zero, size: self.frame.size)
        let canvas = EditingCanvasView(
            image: originalImage,
            frame: canvasFrame,
            existingStrokes: accumulatedStrokes
        )
        canvas.editMode = mode
        canvas.brushSize = lastBrushSize
        canvas.drawColor = lastDrawColor
        canvas.autoresizingMask = [.width, .height]
        self.contentView?.addSubview(canvas)
        self.editingCanvas = canvas

        // Show editing toolbar
        setupEditingToolbar(mode: mode)
    }

    func exitEditingMode(apply: Bool) {
        guard isEditing else { return }
        isEditing = false

        if apply, let canvas = editingCanvas {
            // Save all strokes (old + new) for future undo
            accumulatedStrokes = canvas.strokes
            // Clear redo stack since we have new edits
            redoStack.removeAll()
            // Remember brush settings
            lastBrushSize = canvas.brushSize
            lastDrawColor = canvas.drawColor
            // Composite and update
            if let result = canvas.compositeResult() {
                currentImage = result
                updateImageView()
            }
            // After editing, scroll/GIF no longer apply to the modified image
            if windowMode == .firstPreview {
                windowMode = .pinned
            }
        } else if let canvas = editingCanvas {
            // Even on cancel, remember brush settings
            lastBrushSize = canvas.brushSize
            lastDrawColor = canvas.drawColor
        }

        updateHistoryState()

        // Remove canvas
        editingCanvas?.removeFromSuperview()
        editingCanvas = nil

        // Remove editing toolbar
        if let editToolbar = editingToolbarWindow {
            self.removeChildWindow(editToolbar)
            editToolbar.orderOut(nil)
            editingToolbarWindow = nil
        }

        // Show main toolbar
        if isMouseInside || toolbarAlwaysVisible {
            showHoverUI()
        }
    }

    // MARK: - Undo / Redo

    func performUndo() {
        guard !accumulatedStrokes.isEmpty else { return }
        let stroke = accumulatedStrokes.removeLast()
        redoStack.append(stroke)
        recompositeAndUpdatePreview()
    }

    func performRedo() {
        guard !redoStack.isEmpty else { return }
        let stroke = redoStack.removeLast()
        accumulatedStrokes.append(stroke)
        recompositeAndUpdatePreview()
    }

    private func recompositeAndUpdatePreview() {
        updateHistoryState()

        if accumulatedStrokes.isEmpty {
            currentImage = originalImage
            updateImageView()
        } else {
            let canvasFrame = NSRect(origin: .zero, size: self.frame.size)
            let tempCanvas = EditingCanvasView(
                image: originalImage,
                frame: canvasFrame,
                existingStrokes: accumulatedStrokes
            )
            if let result = tempCanvas.compositeResult() {
                currentImage = result
                updateImageView()
            }
        }
    }

    private func updateHistoryState() {
        historyState.canUndo = !accumulatedStrokes.isEmpty
        historyState.canRedo = !redoStack.isEmpty
    }

    private func updateImageView() {
        let nsImage = NSImage(cgImage: currentImage, size: self.frame.size)
        if let container = self.contentView,
           let imageView = container.subviews.compactMap({ $0 as? DraggableImageView }).first {
            imageView.image = nsImage
        }
    }

    // MARK: - Action Handling

    private func handleAction(_ action: PinAction) {
        switch action {
        case .draw:
            enterEditingMode(mode: .draw)
        case .mosaic:
            enterEditingMode(mode: .mosaic)
        case .undo:
            performUndo()
        case .redo:
            performRedo()
        default:
            onAction?(action, self)
        }
    }

    // MARK: - Main Toolbar

    private func showToolbar() {
        guard toolbarWindow == nil, !isEditing else { return }

        let toolbar = PinToolbar(
            mode: windowMode,
            historyState: historyState
        ) { [weak self] action in
            guard let self else { return }
            self.handleAction(action)
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

    // MARK: - Editing Toolbar

    private func setupEditingToolbar(mode: CanvasEditMode) {
        let toolbarView = EditingToolbar(mode: mode, brushSize: lastBrushSize, color: lastDrawColor) { [weak self] action in
            self?.handleEditingAction(action)
        }
        let hostingView = NSHostingView(rootView: toolbarView)
        hostingView.frame.size = hostingView.fittingSize

        let myFrame = self.frame
        let toolbarRect = CGRect(
            x: myFrame.midX - hostingView.frame.width / 2,
            y: myFrame.origin.y - hostingView.frame.height - 6,
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
        self.editingToolbarWindow = toolbar
    }

    private func handleEditingAction(_ action: EditingAction) {
        guard let canvas = editingCanvas else { return }
        switch action {
        case .setBrushSize(let size):
            canvas.brushSize = size
        case .setColor(let color):
            canvas.drawColor = color
        case .undo:
            canvas.undo()
        case .done:
            exitEditingMode(apply: true)
        case .cancel:
            exitEditingMode(apply: false)
        }
    }

    // MARK: - Dismiss

    func dismiss() {
        hideTimer?.invalidate()
        editingToolbarWindow?.orderOut(nil)
        editingToolbarWindow = nil
        editingCanvas?.removeFromSuperview()
        editingCanvas = nil
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
        if pinWindow.isEditing {
            // Don't drag while editing — let canvas handle mouse events
            super.mouseDown(with: event)
        } else if pinWindow.isInResizeHandle(event.locationInWindow) {
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
    let mode: WindowMode
    @ObservedObject var historyState: EditHistoryState
    let onAction: (PinAction) -> Void

    var body: some View {
        HStack(spacing: 2) {
            pinButton(icon: "doc.on.doc", tooltip: "Copy", action: .copy)
            pinButton(icon: "square.and.arrow.down", tooltip: "Save", action: .save)

            if mode != .gif {
                Divider().frame(height: 20)

                pinButton(icon: "pencil.tip", tooltip: "Draw", action: .draw)
                pinButton(icon: "square.grid.3x3", tooltip: "Mosaic", action: .mosaic)

                if historyState.canUndo || historyState.canRedo {
                    Divider().frame(height: 20)

                    Button {
                        onAction(.undo)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 13))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                            .opacity(historyState.canUndo ? 1 : 0.3)
                    }
                    .buttonStyle(.plain)
                    .disabled(!historyState.canUndo)
                    .help("Undo")

                    Button {
                        onAction(.redo)
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.system(size: 13))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                            .opacity(historyState.canRedo ? 1 : 0.3)
                    }
                    .buttonStyle(.plain)
                    .disabled(!historyState.canRedo)
                    .help("Redo")
                }
            }

            if mode == .firstPreview {
                Divider().frame(height: 20)

                pinButton(icon: "record.circle", tooltip: "Record GIF", action: .recordGif)
                scrollCaptureButton()
            }

            Divider().frame(height: 20)

            pinButton(icon: "xmark", tooltip: mode == .firstPreview ? "Cancel" : "Close", action: .close)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func scrollCaptureButton() -> some View {
        Image(systemName: "arrow.up.and.down.text.horizontal")
            .font(.system(size: 13))
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
            .onTapGesture {
                onAction(.scrollCapture)
            }
            .contextMenu {
                Button("Debug Mode") {
                    onAction(.scrollCaptureDebug)
                }
            }
            .help("Scroll Capture (right-click for debug)")
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
