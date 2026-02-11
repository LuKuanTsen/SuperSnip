import AppKit
import Carbon
import Combine

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
    private var scrollCaptureRect: CGRect?
    private var scrollCaptureBorderWindow: NSPanel?
    private var scrollCaptureDebugMode = false

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

    func startCapture() {
        // Dismiss any existing overlay/preview/scroll capture
        dismissPreview()
        stopScrollCapture()
        dismissOverlays()

        let coordinator = SelectionCoordinator()
        coordinator.delegate = self
        self.selectionCoordinator = coordinator

        for screen in NSScreen.screens {
            let overlay = OverlayWindow(screen: screen)
            let selectionView = overlay.contentView as! SelectionView
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
            dismissPreview()
            ImageExporter.saveWithDialog(imageToSave)
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
            ClipboardManager.copyToClipboard(image)
        case .save:
            pin.dismiss()
            pinWindows.removeAll { $0 === pin }
            ImageExporter.saveWithDialog(image)
        case .close:
            pin.dismiss()
            pinWindows.removeAll { $0 === pin }
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
            var displayWidth = CGFloat(finalImage.width) / scale
            var displayHeight = CGFloat(finalImage.height) / scale
            let maxDisplayHeight: CGFloat = 600.0
            let maxDisplayWidth: CGFloat = 800.0

            if displayHeight > maxDisplayHeight {
                let ratio = maxDisplayHeight / displayHeight
                displayHeight = maxDisplayHeight
                displayWidth *= ratio
            }
            if displayWidth > maxDisplayWidth {
                let ratio = maxDisplayWidth / displayWidth
                displayWidth = maxDisplayWidth
                displayHeight *= ratio
            }

            let screenCenter = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
            let pinRect = CGRect(
                x: screenCenter.midX - displayWidth / 2,
                y: screenCenter.midY - displayHeight / 2,
                width: displayWidth,
                height: displayHeight
            )

            let pin = PinWindow(image: finalImage, frame: pinRect)
            pin.onAction = { [weak self] action, pinWin in
                self?.handlePinAction(action, pin: pinWin)
            }
            pin.makeKeyAndOrderFront(nil)
            self.pinWindows.append(pin)
        }
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
            preview.makeKeyAndOrderFront(nil)
            self.previewWindow = preview
        }
    }

    func selectionDidCancel() {
        dismissOverlays()
    }
}
