import AppKit
import Carbon
import Combine
import UniformTypeIdentifiers

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayWindows: [OverlayWindow] = []
    private var selectionCoordinator: SelectionCoordinator?
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
        // Stop any ongoing scroll capture/GIF recording and dismiss overlays
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

    // MARK: - Pin Actions

    private func handlePinAction(_ action: PinAction, pin: PinWindow) {
        switch action {
        case .copy:
            if let gifData = pin.gifData {
                copyGifToClipboard(gifData)
            } else {
                ClipboardManager.copyToClipboard(pin.currentImage)
            }
        case .save:
            if let gifData = pin.gifData {
                ImageExporter.saveGifAsSheet(gifData, from: pin) {}
            } else {
                ImageExporter.saveAsSheet(pin.currentImage, from: pin) {}
            }
        case .close:
            pin.dismiss()
            pinWindows.removeAll { $0 === pin }
        case .scrollCapture, .scrollCaptureDebug:
            guard let rect = pin.captureRect else { return }
            scrollCaptureDebugMode = (action == .scrollCaptureDebug)
            pin.dismiss()
            pinWindows.removeAll { $0 === pin }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.startScrollCapture(rect: rect)
            }
        case .recordGif:
            guard let rect = pin.captureRect else { return }
            pin.dismiss()
            pinWindows.removeAll { $0 === pin }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.startGifRecording(rect: rect)
            }
        case .draw, .mosaic, .undo, .redo:
            // Handled internally by PinWindow
            break
        }
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

            // Copy to clipboard
            ClipboardManager.copyToClipboard(finalImage)

            // Show in a floating window, scaling to fit screen while maintaining aspect ratio
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            let pinRect = self.centeredPinRect(
                pointWidth: CGFloat(finalImage.width) / scale,
                pointHeight: CGFloat(finalImage.height) / scale
            )

            let pin = PinWindow(image: finalImage, frame: pinRect, mode: .pinned)
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

        // Show indicator with countdown
        let indicator = RecordingIndicator()
        indicator.show(below: rect)
        indicator.onStop = { [weak self] in
            self?.finishGifRecording()
        }
        recordingIndicator = indicator

        // ESC monitor (active during countdown and recording)
        recordingEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.stopGifRecording()
                return nil
            }
            return event
        }
        recordingGlobalEscMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.stopGifRecording()
            }
        }

        // 3-second countdown, then start recording
        indicator.startCountdown(seconds: 3) { [weak self] in
            guard let self else { return }
            self.beginRecording(rect: rect)
        }
    }

    private func beginRecording(rect: CGRect) {
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
            self.copyGifToClipboard(gifData)

            // Show first frame in a floating window (frames are Retina 2x)
            let firstFrame = frames[0]
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            let pinRect = self.centeredPinRect(
                pointWidth: CGFloat(firstFrame.width) / scale,
                pointHeight: CGFloat(firstFrame.height) / scale
            )

            let pin = PinWindow(image: firstFrame, frame: pinRect, mode: .gif)
            pin.gifData = gifData
            pin.onAction = { [weak self] action, pinWin in
                self?.handlePinAction(action, pin: pinWin)
            }
            pin.makeKeyAndOrderFront(nil)
            self.pinWindows.append(pin)
        }
    }

    /// Copy GIF data to clipboard using a temp file URL so receiving apps recognize animated GIF.
    private func copyGifToClipboard(_ gifData: Data) {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("SuperSnip-recording.gif")
        try? gifData.write(to: tempURL)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([tempURL as NSURL])
        pasteboard.setData(gifData, forType: NSPasteboard.PasteboardType(UTType.gif.identifier))
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

            let pin = PinWindow(image: image, frame: rect, mode: .firstPreview, captureRect: rect)
            pin.onAction = { [weak self] action, pinWin in
                self?.handlePinAction(action, pin: pinWin)
            }
            pin.makeKeyAndOrderFront(nil)
            self.pinWindows.append(pin)
        }
    }

    func selectionDidCancel() {
        dismissOverlays()
    }
}
