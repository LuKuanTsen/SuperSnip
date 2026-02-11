import AppKit
import SwiftUI

final class CapturePreviewWindow: NSPanel {
    var onAction: ((ToolbarAction) -> Void)?
    var onImageEdited: ((CGImage) -> Void)?
    private var toolbarWindow: NSPanel?
    private var editingToolbarWindow: NSPanel?
    private var editingCanvas: EditingCanvasView?
    private var isEditing = false
    private var screenRect: CGRect = .zero

    // Persist strokes, redo stack, and brush settings across editing sessions
    private var originalImage: CGImage?
    private var accumulatedStrokes: [Stroke] = []
    private var redoStack: [Stroke] = []
    private var lastBrushSize: BrushSize = .medium
    private var lastDrawColor: NSColor = .systemRed
    private let historyState = EditHistoryState()

    init(image: CGImage, screenRect: CGRect) {
        let imageSize = NSSize(width: screenRect.width, height: screenRect.height)
        self.screenRect = screenRect
        self.originalImage = image

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
        self.isMovableByWindowBackground = true

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
        let toolbarView = ActionToolbar(historyState: historyState) { [weak self] action in
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

    // MARK: - Undo / Redo (from preview toolbar)

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
        guard let original = originalImage else { return }

        if accumulatedStrokes.isEmpty {
            // No strokes — show original
            let nsImage = NSImage(cgImage: original, size: self.frame.size)
            if let imageView = self.contentView as? NSImageView {
                imageView.image = nsImage
            }
            onImageEdited?(original)
        } else {
            // Need a temporary canvas to composite
            let canvasFrame = NSRect(origin: .zero, size: self.frame.size)
            let tempCanvas = EditingCanvasView(
                image: original,
                frame: canvasFrame,
                existingStrokes: accumulatedStrokes
            )
            if let result = tempCanvas.compositeResult() {
                let nsImage = NSImage(cgImage: result, size: self.frame.size)
                if let imageView = self.contentView as? NSImageView {
                    imageView.image = nsImage
                }
                onImageEdited?(result)
            }
        }
    }

    private func updateHistoryState() {
        historyState.canUndo = !accumulatedStrokes.isEmpty
        historyState.canRedo = !redoStack.isEmpty
    }

    // MARK: - Editing Mode

    func enterEditingMode(mode: CanvasEditMode, image: CGImage) {
        guard !isEditing else { return }
        isEditing = true

        // Hide the normal toolbar
        toolbarWindow?.orderOut(nil)

        // Create the editing canvas with the original image and all accumulated strokes
        guard let original = originalImage else { return }
        let canvasFrame = NSRect(origin: .zero, size: self.frame.size)
        let canvas = EditingCanvasView(
            image: original,
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
        setupEditingToolbar(mode: mode, below: screenRect)
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
            // Composite and notify
            if let result = canvas.compositeResult() {
                onImageEdited?(result)
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

        // Restore normal toolbar
        if let toolbar = toolbarWindow {
            self.addChildWindow(toolbar, ordered: .above)
            toolbar.orderFront(nil)
        }
    }

    private func setupEditingToolbar(mode: CanvasEditMode, below rect: CGRect) {
        let toolbarView = EditingToolbar(mode: mode, brushSize: lastBrushSize, color: lastDrawColor) { [weak self] action in
            self?.handleEditingAction(action)
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

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53 {
            if isEditing {
                exitEditingMode(apply: false)
            } else {
                onAction?(.cancel)
            }
        } else if event.keyCode == 6 && flags.contains(.command) && flags.contains(.shift) {
            // Cmd+Shift+Z — redo (only in preview mode)
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

    func dismiss() {
        editingToolbarWindow?.orderOut(nil)
        editingToolbarWindow = nil
        editingCanvas?.removeFromSuperview()
        editingCanvas = nil
        toolbarWindow?.orderOut(nil)
        toolbarWindow = nil
        self.orderOut(nil)
    }
}
