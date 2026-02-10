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
            ImageExporter.saveWithDialog(image)
            dismissPreview()
        case .edit:
            // Phase 3
            break
        case .pin:
            if let rect = capturedRect {
                let pin = PinWindow(image: image, frame: rect)
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
}

// MARK: - SelectionViewDelegate

extension AppDelegate: SelectionViewDelegate {
    func selectionDidComplete(rect: CGRect) {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil

        guard let image = ScreenCaptureManager.capture(rect: rect) else {
            print("Capture failed")
            return
        }
        capturedImage = image
        capturedRect = rect

        let preview = CapturePreviewWindow(image: image, screenRect: rect)
        preview.onAction = { [weak self] action in
            self?.handleToolbarAction(action)
        }
        preview.makeKeyAndOrderFront(nil)
        previewWindow = preview
    }

    func selectionDidCancel() {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
    }
}
