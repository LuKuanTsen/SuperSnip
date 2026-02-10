import AppKit
import Carbon
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayWindow: OverlayWindow?
    private var previewWindow: CapturePreviewWindow?
    private var capturedImage: CGImage?
    private var capturedRect: CGRect?
    private var pinWindows: [PinWindow] = []

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
        // Dismiss any existing overlay/preview
        dismissPreview()
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
            // Phase 4
            break
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
