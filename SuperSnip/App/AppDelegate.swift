import AppKit
import Carbon
import Combine
import UniformTypeIdentifiers

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayWindows: [OverlayWindow] = []
    private var selectionCoordinator: SelectionCoordinator?
    private var previewWindow: CapturePreviewWindow?
    private var capturedImage: CGImage?
    private var capturedRect: CGRect?
    private var pinWindows: [PinWindow] = []

    // Scroll capture
    private var scrollCaptureManager: ScrollCaptureManager?
    private var scrollCaptureIndicator: ScrollCaptureIndicator?
    private var scrollCaptureEscMonitor: Any?
    private var scrollCaptureGlobalEscMonitor: Any?
    private var scrollCaptureRect: CGRect?
    private var scrollCaptureBorderWindow: NSPanel?
    private var scrollCaptureDebugMode = false

    // GIF recording
    private var gifRecordingManager: GifRecordingManager?
    private var recordingIndicator: RecordingIndicator?
    private var recordingEscMonitor: Any?
    private var recordingGlobalEscMonitor: Any?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request screen capture permission
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }

        // Register global hotkey: Cmd+Shift+S
        HotkeyManager.shared.register(
            keyCode: 1, // 'S' key
            modifiers: UInt32(cmdKey | shiftKey),
            handler: { [weak self] in
                DispatchQueue.main.async {
                    self?.startCapture()
                }
            }
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregister()
        stopScrollCapture()
        stopGifRecording()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            startCapture()
        }
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Capture Area", action: #selector(dockCaptureArea), keyEquivalent: ""))
        return menu
    }

    @objc private func dockCaptureArea() {
        startCapture()
    }

    func startCapture() {
        // Dismiss any existing overlay/preview/scroll capture/gif recording
        dismissPreview()
        stopScrollCapture()
        stopGifRecording()
        dismissOverlays()

        let coordinator = SelectionCoordinator()
        coordinator.delegate = self
        self.selectionCoordinator = coordinator

        for screen in NSScreen.screens {
            let overlay = OverlayWindow(screen: screen)
            guard let selectionView = overlay.contentView as? SelectionView else { continue }
            selectionView.coordinator = coordinator
            coordinator.views.append(selectionView)
            overlay.makeKeyAndOrderFront(nil)
            overlayWindows.append(overlay)
        }
    }

    private func dismissOverlays() {
        for overlay in overlayWindows {
            overlay.orderOut(nil)
        }
        overlayWindows.removeAll()
        selectionCoordinator = nil
    }

    private func dismissPreview() {
        previewWindow?.dismiss()
        previewWindow = nil
        capturedImage = nil
        capturedRect = nil
    }

    // MARK: - Toolbar Actions

    private func handleToolbarAction(_ action: ToolbarAction) {
        guard let image = capturedImage else { return }
        switch action {
        case .copy:
            ClipboardManager.copyToClipboard(image)
            dismissPreview()
        case .save:
            let imageToSave = image
            guard let window = previewWindow else { return }
            ImageExporter.saveAsSheet(imageToSave, from: window) { [weak self] in
                self?.dismissPreview()
            }
        case .pin:
            if let rect = capturedRect {
                let pin = PinWindow(image: image, frame: rect)
                pin.onAction = { [weak self] action, pinWin in
                    self?.handlePinAction(action, pin: pinWin)
                }
                pin.makeKeyAndOrderFront(nil)
                pinWindows.append(pin)
            }
            dismissPreview()
        case .cancel:
            dismissPreview()
        case .draw:
            previewWindow?.enterEditingMode(mode: .draw, image: image)
        case .mosaic:
            previewWindow?.enterEditingMode(mode: .mosaic, image: image)
        case .undo:
            previewWindow?.performUndo()
        case .redo:
            previewWindow?.performRedo()
        case .recordGif:
            guard let rect = capturedRect else { return }
            dismissPreview()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.startGifRecording(rect: rect)
            }
        case .scrollCapture, .scrollCaptureDebug:
            guard let rect = capturedRect else { return }
            scrollCaptureDebugMode = (action == .scrollCaptureDebug)
            dismissPreview()
            // Delay to let preview window fully disappear before first capture
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.startScrollCapture(rect: rect)
            }
        }
    }

    // MARK: - Pin Actions

    private func handlePinAction(_ action: PinAction, pin: PinWindow) {
        let image = pin.pinnedImage
        switch action {
        case .copy:
            if let gifData = pin.gifData {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setData(gifData, forType: NSPasteboard.PasteboardType(UTType.gif.identifier))
            } else {
                ClipboardManager.copyToClipboard(image)
            }
        case .save:
            let gifData = pin.gifData
            let completion: () -> Void = { [weak self] in
                pin.dismiss()
                self?.pinWindows.removeAll { $0 === pin }
            }
            if let gifData {
                ImageExporter.saveGifAsSheet(gifData, from: pin, completion: completion)
            } else {
                ImageExporter.saveAsSheet(image, from: pin, completion: completion)
            }
        case .close:
            pin.dismiss()
            pinWindows.removeAll { $0 === pin }
        case .draw, .mosaic:
            let pinFrame = pin.frame
            pin.dismiss()
            pinWindows.removeAll { $0 === pin }
            openEditorForImage(image, frame: pinFrame, mode: action == .draw ? .draw : .mosaic)
        }
    }

    private func openEditorForImage(_ image: CGImage, frame: CGRect, mode: CanvasEditMode) {
        dismissPreview()
        capturedImage = image
        capturedRect = frame

        let preview = CapturePreviewWindow(image: image, screenRect: frame)
        preview.onAction = { [weak self] action in
            self?.handleToolbarAction(action)
        }
        preview.onImageEdited = { [weak self] editedImage in
            guard let self else { return }
            self.capturedImage = editedImage
            let nsImage = NSImage(cgImage: editedImage, size: NSSize(width: frame.width, height: frame.height))
            if let imageView = self.previewWindow?.contentView as? NSImageView {
                imageView.image = nsImage
            }
        }
        preview.makeKeyAndOrderFront(nil)
        self.previewWindow = preview

        // Immediately enter editing mode
        preview.enterEditingMode(mode: mode, image: image)
    }

    // MARK: - Scroll Capture

    private func startScrollCapture(rect: CGRect) {
        scrollCaptureRect = rect

        // Show a border around the capture area so the user knows what region is being monitored
        showScrollCaptureBorder(rect: rect)

        // Show the floating indicator
        let indicator = ScrollCaptureIndicator()
        indicator.show(below: rect)
        indicator.onStop = { [weak self] in
            self?.finishScrollCapture()
        }
        scrollCaptureIndicator = indicator

        // Start capturing
        let manager = ScrollCaptureManager(rect: rect)
        scrollCaptureManager = manager
        manager.start(
            onFrameAdded: { [weak self] count in
                DispatchQueue.main.async {
                    self?.scrollCaptureIndicator?.updateFrameCount(count)
                }
            },
            onComplete: { [weak self] frames in
                self?.handleScrollCaptureComplete(frames: frames)
            }
        )

        // Monitor ESC to stop (both local and global)
        scrollCaptureEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                self?.finishScrollCapture()
                return nil
            }
            return event
        }
        scrollCaptureGlobalEscMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.finishScrollCapture()
            }
        }
    }

    private func finishScrollCapture() {
        scrollCaptureManager?.stop()
        // Cleanup happens in handleScrollCaptureComplete
    }

    private func stopScrollCapture() {
        if let monitor = scrollCaptureEscMonitor {
            NSEvent.removeMonitor(monitor)
            scrollCaptureEscMonitor = nil
        }
        if let monitor = scrollCaptureGlobalEscMonitor {
            NSEvent.removeMonitor(monitor)
            scrollCaptureGlobalEscMonitor = nil
        }
        scrollCaptureIndicator?.dismiss()
        scrollCaptureIndicator = nil
        scrollCaptureManager?.stop()
        scrollCaptureManager = nil
        scrollCaptureBorderWindow?.orderOut(nil)
        scrollCaptureBorderWindow = nil
        scrollCaptureRect = nil
    }

    private func handleScrollCaptureComplete(frames: [CGImage]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            // Clean up UI
            if let monitor = self.scrollCaptureEscMonitor {
                NSEvent.removeMonitor(monitor)
                self.scrollCaptureEscMonitor = nil
            }
            if let monitor = self.scrollCaptureGlobalEscMonitor {
                NSEvent.removeMonitor(monitor)
                self.scrollCaptureGlobalEscMonitor = nil
            }
            self.scrollCaptureIndicator?.dismiss()
            self.scrollCaptureIndicator = nil
            self.scrollCaptureBorderWindow?.orderOut(nil)
            self.scrollCaptureBorderWindow = nil

            guard !frames.isEmpty else {
                self.scrollCaptureManager = nil
                return
            }

            // Stitch frames with debug info
            let (stitched, debugInfo): (CGImage?, StitchDebugInfo)
            if frames.count == 1 {
                stitched = frames.first
                debugInfo = StitchDebugInfo(pairs: [], validIndices: [0], validOverlaps: [], frameCount: 1)
            } else {
                (stitched, debugInfo) = ImageStitcher.stitchWithDebug(frames: frames)
            }

            // Save debug output only in debug mode
            if self.scrollCaptureDebugMode {
                let timestamp = ISO8601DateFormatter().string(from: Date())
                    .replacingOccurrences(of: ":", with: "-")
                let debugDir = "/tmp/super-snip-debug/\(timestamp)"
                ImageStitcher.saveDebug(frames: frames, result: stitched, debug: debugInfo, to: debugDir)
                NSWorkspace.shared.open(URL(fileURLWithPath: debugDir))
                print(debugInfo.log)
            }

            guard let finalImage = stitched else {
                self.scrollCaptureManager = nil
                return
            }

            self.scrollCaptureManager = nil

            // Show the result — copy to clipboard and show a preview
            ClipboardManager.copyToClipboard(finalImage)

            // Show in a pin window, scaling to fit screen while maintaining aspect ratio
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            let pinRect = self.centeredPinRect(
                pointWidth: CGFloat(finalImage.width) / scale,
                pointHeight: CGFloat(finalImage.height) / scale
            )

            let pin = PinWindow(image: finalImage, frame: pinRect)
            pin.onAction = { [weak self] action, pinWin in
                self?.handlePinAction(action, pin: pinWin)
            }
            pin.makeKeyAndOrderFront(nil)
            self.pinWindows.append(pin)
        }
    }

    // MARK: - GIF Recording

    private var gifRecordingStartTime: Date?
    private var gifRecordingTimer: Timer?

    private func startGifRecording(rect: CGRect) {
        // Show border
        showScrollCaptureBorder(rect: rect)

        // Show indicator
        let indicator = RecordingIndicator()
        indicator.show(below: rect)
        indicator.onStop = { [weak self] in
            self?.finishGifRecording()
        }
        recordingIndicator = indicator

        // Start recording
        let manager = GifRecordingManager(rect: rect)
        gifRecordingManager = manager
        gifRecordingStartTime = Date()

        // Timer for elapsed time display
        gifRecordingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let start = self.gifRecordingStartTime else { return }
            self.recordingIndicator?.updateElapsedTime(Date().timeIntervalSince(start))
        }

        manager.start(
            onFrameAdded: { [weak self] count in
                DispatchQueue.main.async {
                    self?.recordingIndicator?.updateFrameCount(count)
                }
            },
            onComplete: { [weak self] frames in
                self?.handleGifRecordingComplete(frames: frames)
            }
        )

        // ESC monitor (local + global, since user may be in another app)
        recordingEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.finishGifRecording()
                return nil
            }
            return event
        }
        recordingGlobalEscMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.finishGifRecording()
            }
        }
    }

    private func finishGifRecording() {
        gifRecordingManager?.stop()
    }

    private func stopGifRecording() {
        gifRecordingTimer?.invalidate()
        gifRecordingTimer = nil
        gifRecordingStartTime = nil
        if let monitor = recordingEscMonitor {
            NSEvent.removeMonitor(monitor)
            recordingEscMonitor = nil
        }
        if let monitor = recordingGlobalEscMonitor {
            NSEvent.removeMonitor(monitor)
            recordingGlobalEscMonitor = nil
        }
        recordingIndicator?.dismiss()
        recordingIndicator = nil
        gifRecordingManager = nil
        scrollCaptureBorderWindow?.orderOut(nil)
        scrollCaptureBorderWindow = nil
    }

    private func handleGifRecordingComplete(frames: [CGImage]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            // Clean up UI
            self.gifRecordingTimer?.invalidate()
            self.gifRecordingTimer = nil
            self.gifRecordingStartTime = nil
            if let monitor = self.recordingEscMonitor {
                NSEvent.removeMonitor(monitor)
                self.recordingEscMonitor = nil
            }
            if let monitor = self.recordingGlobalEscMonitor {
                NSEvent.removeMonitor(monitor)
                self.recordingGlobalEscMonitor = nil
            }
            self.recordingIndicator?.dismiss()
            self.recordingIndicator = nil
            self.scrollCaptureBorderWindow?.orderOut(nil)
            self.scrollCaptureBorderWindow = nil

            guard !frames.isEmpty else {
                self.gifRecordingManager = nil
                return
            }

            // Encode to GIF
            let frameDelay = self.gifRecordingManager?.frameDelay ?? (1.0 / 8.0)
            self.gifRecordingManager = nil
            guard let gifData = GifEncoder.encodeToData(frames: frames, frameDelay: frameDelay) else {
                print("GIF encoding failed")
                return
            }

            // Copy GIF data to clipboard
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(gifData, forType: NSPasteboard.PasteboardType(UTType.gif.identifier))

            // Show first frame in a pin window (frames are already 1x point size)
            let firstFrame = frames[0]
            let pinRect = self.centeredPinRect(
                pointWidth: CGFloat(firstFrame.width),
                pointHeight: CGFloat(firstFrame.height)
            )

            let pin = PinWindow(image: firstFrame, frame: pinRect)
            pin.gifData = gifData
            pin.onAction = { [weak self] action, pinWin in
                self?.handlePinAction(action, pin: pinWin)
            }
            pin.makeKeyAndOrderFront(nil)
            self.pinWindows.append(pin)
        }
    }

    /// Compute a centered pin window rect that fits within max display bounds.
    /// `pointWidth`/`pointHeight` should already be in point dimensions (not pixels).
    private func centeredPinRect(pointWidth: CGFloat, pointHeight: CGFloat) -> CGRect {
        var w = pointWidth
        var h = pointHeight
        let maxH: CGFloat = 600, maxW: CGFloat = 800

        if h > maxH { let r = maxH / h; h = maxH; w *= r }
        if w > maxW { let r = maxW / w; w = maxW; h *= r }

        let screen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        return CGRect(x: screen.midX - w / 2, y: screen.midY - h / 2, width: w, height: h)
    }

    private func showScrollCaptureBorder(rect: CGRect) {
        let gap: CGFloat = 3  // gap between capture area and border
        let borderWidth: CGFloat = 2
        let outset = gap + borderWidth
        let borderWindow = NSPanel(
            contentRect: rect.insetBy(dx: -outset, dy: -outset),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        borderWindow.level = .floating
        borderWindow.isOpaque = false
        borderWindow.backgroundColor = .clear
        borderWindow.ignoresMouseEvents = true
        borderWindow.hasShadow = false

        let borderView = NSView(frame: NSRect(origin: .zero, size: rect.insetBy(dx: -outset, dy: -outset).size))
        borderView.wantsLayer = true
        borderView.layer?.borderColor = NSColor.systemOrange.cgColor
        borderView.layer?.borderWidth = borderWidth
        borderView.layer?.cornerRadius = 3
        borderWindow.contentView = borderView

        borderWindow.orderFront(nil)
        scrollCaptureBorderWindow = borderWindow
    }
}

// MARK: - SelectionViewDelegate

extension AppDelegate: SelectionViewDelegate {
    func selectionDidComplete(rect: CGRect) {
        dismissOverlays()

        // Wait for the overlay to be fully removed from screen before capturing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            guard let image = ScreenCaptureManager.capture(rect: rect) else {
                print("Capture failed")
                return
            }
            self.capturedImage = image
            self.capturedRect = rect

            let preview = CapturePreviewWindow(image: image, screenRect: rect)
            preview.onAction = { [weak self] action in
                self?.handleToolbarAction(action)
            }
            preview.onImageEdited = { [weak self] editedImage in
                guard let self else { return }
                self.capturedImage = editedImage
                // Update the preview image view
                let nsImage = NSImage(cgImage: editedImage, size: NSSize(width: rect.width, height: rect.height))
                if let imageView = self.previewWindow?.contentView as? NSImageView {
                    imageView.image = nsImage
                }
            }
            preview.makeKeyAndOrderFront(nil)
            self.previewWindow = preview
        }
    }

    func selectionDidCancel() {
        dismissOverlays()
    }
}
