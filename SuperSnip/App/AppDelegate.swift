import AppKit
import Carbon
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayWindow: OverlayWindow?
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
        overlayWindow?.orderOut(nil)

        let overlay = OverlayWindow()
        overlay.setSelectionDelegate(self)
        overlay.makeKeyAndOrderFront(nil)
        self.overlayWindow = overlay
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
        case .edit:
            // Phase 3
            break
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
        case .scrollCapture:
            guard let rect = capturedRect else { return }
            dismissPreview()
            startScrollCapture(rect: rect)
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
        case .edit:
            // Phase 3
            break
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

            // Stitch frames
            let stitched: CGImage?
            if frames.count == 1 {
                stitched = frames.first
            } else {
                stitched = ImageStitcher.stitch(frames: frames)
            }

            guard let finalImage = stitched else {
                self.scrollCaptureManager = nil
                return
            }

            self.scrollCaptureManager = nil

            // Show the result — copy to clipboard and show a preview
            ClipboardManager.copyToClipboard(finalImage)

            // Show in a pin window so the user can see the result and save/copy
            let displayHeight = min(CGFloat(finalImage.height) / 2, 600.0) // Cap display height
            let displayWidth = CGFloat(finalImage.width) / 2
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
        let borderWindow = NSPanel(
            contentRect: rect.insetBy(dx: -2, dy: -2),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        borderWindow.level = .floating
        borderWindow.isOpaque = false
        borderWindow.backgroundColor = .clear
        borderWindow.ignoresMouseEvents = true
        borderWindow.hasShadow = false

        let borderView = NSView(frame: NSRect(origin: .zero, size: rect.insetBy(dx: -2, dy: -2).size))
        borderView.wantsLayer = true
        borderView.layer?.borderColor = NSColor.systemOrange.cgColor
        borderView.layer?.borderWidth = 2
        borderView.layer?.cornerRadius = 2
        borderWindow.contentView = borderView

        borderWindow.orderFront(nil)
        scrollCaptureBorderWindow = borderWindow
    }
}

// MARK: - SelectionViewDelegate

extension AppDelegate: SelectionViewDelegate {
    func selectionDidComplete(rect: CGRect) {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil

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
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
    }
}
