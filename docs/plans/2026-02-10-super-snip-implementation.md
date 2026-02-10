# Super Snip Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a native macOS menu bar screenshot tool with area capture, in-place preview with action toolbar, annotation editing, and scrolling capture.

**Architecture:** SwiftUI @main app with MenuBarExtra, AppKit NSPanel windows for overlay/preview/pin. CGWindowListCreateImage for capture (broad compatibility). Core Graphics for annotation rendering.

**Tech Stack:** Swift, SwiftUI, AppKit, ScreenCaptureKit/CoreGraphics, Carbon (global hotkey)

---

### Task 1: Create Xcode Project Structure

**Files:**
- Create: `SuperSnip.xcodeproj` (via xcodebuild)
- Create: `SuperSnip/SuperSnipApp.swift`
- Create: `SuperSnip/Info.plist`
- Create: `SuperSnip/SuperSnip.entitlements`

**Step 1: Initialize the Swift Package and Xcode project**

Create the project directory structure:

```
SuperSnip/
  SuperSnip/
    App/
    Capture/
    Preview/
    Editor/
    Editor/Tools/
    ScrollCapture/
    Utilities/
    Resources/
```

**Step 2: Create Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Super Snip</string>
    <key>CFBundleIdentifier</key>
    <string>com.supersnip.app</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Super Snip needs screen recording permission to capture screenshots.</string>
</dict>
</plist>
```

Key entries:
- `LSUIElement = true` — hides from Dock, menu bar only
- `NSScreenCaptureUsageDescription` — permission prompt text

**Step 3: Create entitlements file**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
```

Note: We disable sandbox because screen capture requires it. For App Store distribution later, we'd use a temporary exception entitlement.

**Step 4: Create the SwiftUI app entry point**

File: `SuperSnip/App/SuperSnipApp.swift`

```swift
import SwiftUI

@main
struct SuperSnipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Super Snip", systemImage: "scissors") {
            Button("Capture Area") {
                appDelegate.startCapture()
            }
            .keyboardShortcut("4", modifiers: [.command, .shift])
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
```

**Step 5: Create AppDelegate**

File: `SuperSnip/App/AppDelegate.swift`

```swift
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register global hotkey in Task 3
    }

    func startCapture() {
        print("Starting capture...") // Placeholder
    }
}
```

**Step 6: Create Package.swift for building**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SuperSnip",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SuperSnip",
            path: "SuperSnip",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Carbon"),
            ]
        ),
    ]
)
```

**Step 7: Build and run to verify menu bar icon appears**

```bash
cd SuperSnip && swift build
# Or: open SuperSnip.xcodeproj if using Xcode
```

Expected: App builds. Menu bar icon (scissors) appears. Clicking shows "Capture Area" and "Quit".

**Step 8: Commit**

```bash
git init && git add -A && git commit -m "feat: initial project setup with menu bar app"
```

---

### Task 2: Global Hotkey Registration

**Files:**
- Create: `SuperSnip/Utilities/HotkeyManager.swift`
- Modify: `SuperSnip/App/AppDelegate.swift`

**Step 1: Create HotkeyManager using Carbon API**

File: `SuperSnip/Utilities/HotkeyManager.swift`

Carbon's `RegisterEventHotKey` is the most reliable way to register system-wide hotkeys that work even when the app is not focused.

```swift
import Carbon
import AppKit

final class HotkeyManager {
    private var hotkeyRef: EventHotKeyRef?
    private var onTrigger: (() -> Void)?

    static let shared = HotkeyManager()

    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        onTrigger = handler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.onTrigger?()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )

        var hotkeyID = EventHotKeyID(signature: OSType(0x5353_4E50), id: 1) // "SSNP"
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        if status != noErr {
            print("Failed to register hotkey: \(status)")
        }
    }

    func unregister() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
    }
}
```

**Step 2: Wire hotkey to AppDelegate**

Modify `AppDelegate.applicationDidFinishLaunching`:

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    // Cmd+Shift+S (keyCode 1 = 'S', cmdKey | shiftKey)
    HotkeyManager.shared.register(
        keyCode: 1, // 'S' key
        modifiers: UInt32(cmdKey | shiftKey),
        handler: { [weak self] in
            self?.startCapture()
        }
    )
}
```

**Step 3: Build and verify**

```bash
swift build && .build/debug/SuperSnip
```

Expected: Press Cmd+Shift+S → "Starting capture..." prints to console.

**Step 4: Commit**

```bash
git add -A && git commit -m "feat: add global hotkey registration (Cmd+Shift+S)"
```

---

### Task 3: Full-Screen Overlay Window

**Files:**
- Create: `SuperSnip/Capture/OverlayWindow.swift`
- Modify: `SuperSnip/App/AppDelegate.swift`

**Step 1: Create OverlayWindow**

A transparent NSPanel that covers all screens to capture mouse events for region selection.

File: `SuperSnip/Capture/OverlayWindow.swift`

```swift
import AppKit

final class OverlayWindow: NSPanel {
    init() {
        // Union of all screen frames to cover all displays
        let fullFrame = NSScreen.screens.reduce(CGRect.zero) { $0.union($1.frame) }

        super.init(
            contentRect: fullFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = NSColor.black.withAlphaComponent(0.3)
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
```

**Step 2: Wire to AppDelegate**

```swift
private var overlayWindow: OverlayWindow?

func startCapture() {
    let overlay = OverlayWindow()
    overlay.makeKeyAndOrderFront(nil)
    self.overlayWindow = overlay
}
```

**Step 3: Build and test**

Expected: Pressing Cmd+Shift+S shows a dark semi-transparent overlay covering all screens. (Cannot dismiss yet — that's next task.)

**Step 4: Commit**

```bash
git add -A && git commit -m "feat: add full-screen overlay window for capture"
```

---

### Task 4: Region Selection with Mouse Drag

**Files:**
- Create: `SuperSnip/Capture/SelectionView.swift`
- Modify: `SuperSnip/Capture/OverlayWindow.swift`
- Modify: `SuperSnip/App/AppDelegate.swift`

**Step 1: Create SelectionView**

An NSView that handles mouse drag to select a rectangular region, draws the selection rectangle with dimension label, and supports ESC to cancel.

File: `SuperSnip/Capture/SelectionView.swift`

```swift
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
            // Too small, treat as cancel
            delegate?.selectionDidCancel()
            return
        }
        // Convert to screen coordinates
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
        guard let rect = selectionRect else { return }

        // Clear selection area (show original screen through the selection)
        NSColor.clear.setFill()
        let path = NSBezierPath(rect: rect)
        path.fill()

        // Draw selection border
        NSColor.systemBlue.setStroke()
        let borderPath = NSBezierPath(rect: rect)
        borderPath.lineWidth = 1.5
        borderPath.stroke()

        // Draw corner handles
        let handleSize: CGFloat = 6
        NSColor.white.setFill()
        for point in cornerPoints(of: rect) {
            let handleRect = CGRect(
                x: point.x - handleSize / 2,
                y: point.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            let handle = NSBezierPath(ovalIn: handleRect)
            handle.fill()
            NSColor.systemBlue.setStroke()
            handle.lineWidth = 1
            handle.stroke()
        }

        // Draw dimension label
        drawDimensionLabel(for: rect)
    }

    private func cornerPoints(of rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.midY),
            CGPoint(x: rect.maxX, y: rect.midY),
        ]
    }

    private func drawDimensionLabel(for rect: CGRect) {
        let text = "\(Int(rect.width)) × \(Int(rect.height)) pt"
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
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: bgRect, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(
            at: CGPoint(x: bgRect.origin.x + padding, y: bgRect.origin.y + padding / 2),
            withAttributes: attrs
        )
    }
}
```

**Step 2: Wire SelectionView into OverlayWindow**

Add to `OverlayWindow.init()`:

```swift
let selectionView = SelectionView(frame: fullFrame)
selectionView.autoresizingMask = [.width, .height]
self.contentView = selectionView
```

Add a method to set the delegate:

```swift
func setSelectionDelegate(_ delegate: SelectionViewDelegate) {
    (contentView as? SelectionView)?.delegate = delegate
}
```

**Step 3: Implement delegate in AppDelegate**

```swift
extension AppDelegate: SelectionViewDelegate {
    func selectionDidComplete(rect: CGRect) {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        print("Selected region: \(rect)")
        // Next task: capture this region
    }

    func selectionDidCancel() {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
    }
}
```

Update `startCapture()`:

```swift
func startCapture() {
    let overlay = OverlayWindow()
    overlay.setSelectionDelegate(self)
    overlay.makeKeyAndOrderFront(nil)
    self.overlayWindow = overlay
}
```

**Step 4: Build and test**

Expected: Cmd+Shift+S → dark overlay → crosshair cursor → drag to select region (blue border, corner handles, dimension label) → release prints rect → ESC cancels.

**Step 5: Commit**

```bash
git add -A && git commit -m "feat: add region selection with drag, dimension label, ESC cancel"
```

---

### Task 5: Screen Capture

**Files:**
- Create: `SuperSnip/Capture/ScreenCaptureManager.swift`
- Modify: `SuperSnip/App/AppDelegate.swift`

**Step 1: Create ScreenCaptureManager**

Uses `CGWindowListCreateImage` for broad macOS compatibility. The rect must be in CoreGraphics screen coordinates (origin at top-left of primary display).

File: `SuperSnip/Capture/ScreenCaptureManager.swift`

```swift
import AppKit
import CoreGraphics

final class ScreenCaptureManager {
    /// Capture a screen region. `rect` is in AppKit screen coordinates (origin bottom-left).
    static func capture(rect: CGRect) -> CGImage? {
        // Convert AppKit coordinates (origin bottom-left) to CG coordinates (origin top-left)
        guard let mainScreen = NSScreen.screens.first else { return nil }
        let screenHeight = mainScreen.frame.height
        let cgRect = CGRect(
            x: rect.origin.x,
            y: screenHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
        return CGWindowListCreateImage(
            cgRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        )
    }
}
```

**Step 2: Wire capture to selection completion**

In `AppDelegate.selectionDidComplete`:

```swift
func selectionDidComplete(rect: CGRect) {
    overlayWindow?.orderOut(nil)
    overlayWindow = nil

    guard let image = ScreenCaptureManager.capture(rect: rect) else {
        print("Capture failed")
        return
    }
    print("Captured image: \(image.width)x\(image.height)")
    // Next task: show preview window
}
```

**Step 3: Build and test**

Expected: Select a region → overlay closes → console prints captured image dimensions (should be 2x the pt dimensions on Retina displays).

**Step 4: Commit**

```bash
git add -A && git commit -m "feat: capture selected region using CGWindowListCreateImage"
```

---

### Task 6: Clipboard and Save Utilities

**Files:**
- Create: `SuperSnip/Utilities/ClipboardManager.swift`
- Create: `SuperSnip/Utilities/ImageExporter.swift`

**Step 1: Create ClipboardManager**

File: `SuperSnip/Utilities/ClipboardManager.swift`

```swift
import AppKit

final class ClipboardManager {
    static func copyToClipboard(_ image: CGImage) {
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([nsImage])
    }
}
```

**Step 2: Create ImageExporter**

File: `SuperSnip/Utilities/ImageExporter.swift`

```swift
import AppKit
import UniformTypeIdentifiers

final class ImageExporter {
    static func saveWithDialog(_ image: CGImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = "screenshot.png"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let isPNG = url.pathExtension.lowercased() == "png"
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL,
            (isPNG ? UTType.png.identifier : UTType.jpeg.identifier) as CFString,
            1, nil
        ) else { return }

        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
```

**Step 3: Commit**

```bash
git add -A && git commit -m "feat: add clipboard copy and save-to-file utilities"
```

---

### Task 7: Preview Window with Action Toolbar

**Files:**
- Create: `SuperSnip/Preview/CapturePreviewWindow.swift`
- Create: `SuperSnip/Preview/ActionToolbar.swift`
- Modify: `SuperSnip/App/AppDelegate.swift`

**Step 1: Create ActionToolbar**

A SwiftUI view with icon buttons for copy, save, edit, pin, cancel.

File: `SuperSnip/Preview/ActionToolbar.swift`

```swift
import SwiftUI

enum ToolbarAction {
    case copy
    case save
    case edit
    case pin
    case cancel
}

struct ActionToolbar: View {
    let onAction: (ToolbarAction) -> Void

    var body: some View {
        HStack(spacing: 2) {
            toolbarButton(icon: "pin", tooltip: "Pin to screen", action: .pin)

            Divider().frame(height: 20)

            toolbarButton(icon: "square.and.arrow.down", tooltip: "Save", action: .save)
            toolbarButton(icon: "doc.on.doc", tooltip: "Copy", action: .copy)

            Divider().frame(height: 20)

            toolbarButton(icon: "pencil.and.outline", tooltip: "Edit", action: .edit)

            Divider().frame(height: 20)

            toolbarButton(icon: "xmark", tooltip: "Cancel", action: .cancel)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func toolbarButton(icon: String, tooltip: String, action: ToolbarAction) -> some View {
        Button {
            onAction(action)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}
```

**Step 2: Create CapturePreviewWindow**

An NSPanel positioned at the captured region, showing the screenshot with the toolbar below.

File: `SuperSnip/Preview/CapturePreviewWindow.swift`

```swift
import AppKit
import SwiftUI

final class CapturePreviewWindow: NSPanel {
    var onAction: ((ToolbarAction) -> Void)?
    private var toolbarWindow: NSPanel?

    init(image: CGImage, screenRect: CGRect) {
        let imageSize = NSSize(width: screenRect.width, height: screenRect.height)
        let toolbarHeight: CGFloat = 44
        let totalRect = CGRect(
            x: screenRect.origin.x,
            y: screenRect.origin.y - toolbarHeight - 8,
            width: screenRect.width,
            height: screenRect.height + toolbarHeight + 8
        )

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

        // Image view
        let nsImage = NSImage(cgImage: image, size: imageSize)
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: imageSize))
        imageView.image = nsImage
        imageView.imageScaling = .scaleAxesIndependently
        self.contentView = imageView

        // Selection border
        let borderView = NSView(frame: NSRect(origin: .zero, size: imageSize))
        borderView.wantsLayer = true
        borderView.layer?.borderColor = NSColor.systemBlue.cgColor
        borderView.layer?.borderWidth = 1.5
        imageView.addSubview(borderView)

        // Toolbar as a child window
        setupToolbar(below: screenRect)
    }

    private func setupToolbar(below rect: CGRect) {
        let toolbarView = ActionToolbar { [weak self] action in
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

    func dismiss() {
        toolbarWindow?.orderOut(nil)
        self.orderOut(nil)
    }
}
```

**Step 3: Wire preview to AppDelegate**

```swift
private var previewWindow: CapturePreviewWindow?
private var capturedImage: CGImage?
private var capturedRect: CGRect?

func selectionDidComplete(rect: CGRect) {
    overlayWindow?.orderOut(nil)
    overlayWindow = nil

    guard let image = ScreenCaptureManager.capture(rect: rect) else { return }
    capturedImage = image
    capturedRect = rect

    let preview = CapturePreviewWindow(image: image, screenRect: rect)
    preview.onAction = { [weak self] action in
        self?.handleToolbarAction(action)
    }
    preview.makeKeyAndOrderFront(nil)
    previewWindow = preview
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
        break // Task 9
    case .pin:
        break // Task 8
    case .cancel:
        dismissPreview()
    }
}

private func dismissPreview() {
    previewWindow?.dismiss()
    previewWindow = nil
    capturedImage = nil
    capturedRect = nil
}
```

**Step 4: Build and test**

Expected: Capture region → screenshot appears at exact position with blue border → toolbar below with icons → Copy copies to clipboard (verify by pasting in Preview.app) → Save opens save dialog → Cancel dismisses.

**Step 5: Commit**

```bash
git add -A && git commit -m "feat: add capture preview window with action toolbar"
```

---

### Task 8: Pin to Screen

**Files:**
- Create: `SuperSnip/Preview/PinWindow.swift`
- Modify: `SuperSnip/App/AppDelegate.swift`

**Step 1: Create PinWindow**

A floating, draggable, resizable window that shows the pinned screenshot. Close button appears on hover.

File: `SuperSnip/Preview/PinWindow.swift`

```swift
import AppKit

final class PinWindow: NSPanel {
    private let imageView: NSImageView
    private let closeButton: NSButton

    init(image: CGImage, frame: CGRect) {
        let nsImage = NSImage(cgImage: image, size: NSSize(width: frame.width, height: frame.height))

        imageView = NSImageView()
        imageView.image = nsImage
        imageView.imageScaling = .scaleProportionallyUpOrDown

        closeButton = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")!,
                               target: nil, action: nil)
        closeButton.isBordered = false
        closeButton.isHidden = true

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        imageView.frame = container.bounds
        imageView.autoresizingMask = [.width, .height]
        container.addSubview(imageView)

        closeButton.frame = NSRect(x: frame.width - 24, y: frame.height - 24, width: 20, height: 20)
        closeButton.autoresizingMask = [.minXMargin, .minYMargin]
        closeButton.target = self
        closeButton.action = #selector(closePinWindow)
        container.addSubview(closeButton)

        self.contentView = container

        // Track mouse for showing/hiding close button
        let trackingArea = NSTrackingArea(
            rect: container.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        container.addTrackingArea(trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        closeButton.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        closeButton.isHidden = true
    }

    @objc private func closePinWindow() {
        self.orderOut(nil)
    }
}
```

**Step 2: Wire pin action in AppDelegate**

```swift
private var pinWindows: [PinWindow] = []

// In handleToolbarAction, case .pin:
case .pin:
    if let rect = capturedRect {
        let pin = PinWindow(image: image, frame: rect)
        pin.makeKeyAndOrderFront(nil)
        pinWindows.append(pin)
    }
    dismissPreview()
```

**Step 3: Build and test**

Expected: Capture → Pin → screenshot floats on top of all windows → draggable → hover shows close button → close button dismisses → can pin multiple screenshots.

**Step 4: Commit**

```bash
git add -A && git commit -m "feat: add pin-to-screen floating window"
```

---

### Task 9: Annotation Data Model

**Files:**
- Create: `SuperSnip/Editor/AnnotationState.swift`

**Step 1: Define annotation types and state**

The data model for annotations, independent of UI. Each annotation is an immutable struct. Undo/redo is a simple stack.

File: `SuperSnip/Editor/AnnotationState.swift`

```swift
import AppKit

enum AnnotationTool: String, CaseIterable {
    case line
    case rectangle
    case ellipse
    case mosaic
}

struct Annotation: Identifiable {
    let id = UUID()
    let tool: AnnotationTool
    let points: [CGPoint]        // start + end for shapes, multiple for freehand/mosaic
    let color: NSColor
    let strokeWidth: CGFloat
    let mosaicBlockSize: Int     // only used for mosaic tool
}

final class AnnotationState: ObservableObject {
    @Published var annotations: [Annotation] = []
    @Published var currentTool: AnnotationTool = .line
    @Published var currentColor: NSColor = .systemRed
    @Published var currentStrokeWidth: CGFloat = 3.0
    @Published var mosaicBlockSize: Int = 10

    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []

    func addAnnotation(_ annotation: Annotation) {
        undoStack.append(annotations)
        redoStack.removeAll()
        annotations.append(annotation)
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
}
```

**Step 2: Commit**

```bash
git add -A && git commit -m "feat: add annotation data model with undo/redo"
```

---

### Task 10: Annotation Canvas (Core Graphics Rendering)

**Files:**
- Create: `SuperSnip/Editor/AnnotationCanvas.swift`

**Step 1: Create AnnotationCanvas**

An NSView that renders the base image and all annotations using Core Graphics. Handles mouse events for drawing.

File: `SuperSnip/Editor/AnnotationCanvas.swift`

```swift
import AppKit

protocol AnnotationCanvasDelegate: AnyObject {
    func canvasDidAddAnnotation(_ annotation: Annotation)
}

final class AnnotationCanvas: NSView {
    weak var delegate: AnnotationCanvasDelegate?

    var baseImage: CGImage?
    var annotations: [Annotation] = [] { didSet { needsDisplay = true } }
    var currentTool: AnnotationTool = .line
    var currentColor: NSColor = .systemRed
    var currentStrokeWidth: CGFloat = 3.0
    var mosaicBlockSize: Int = 10

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var mosaicPoints: [CGPoint] = []

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Draw base image
        if let image = baseImage {
            ctx.draw(image, in: bounds)
        }

        // Draw committed annotations
        for annotation in annotations {
            drawAnnotation(annotation, in: ctx)
        }

        // Draw in-progress annotation
        if let start = dragStart, let current = dragCurrent {
            let inProgress: Annotation
            if currentTool == .mosaic {
                inProgress = Annotation(
                    tool: .mosaic, points: mosaicPoints + [current],
                    color: currentColor, strokeWidth: currentStrokeWidth,
                    mosaicBlockSize: mosaicBlockSize
                )
            } else {
                inProgress = Annotation(
                    tool: currentTool, points: [start, current],
                    color: currentColor, strokeWidth: currentStrokeWidth,
                    mosaicBlockSize: mosaicBlockSize
                )
            }
            drawAnnotation(inProgress, in: ctx)
        }
    }

    private func drawAnnotation(_ annotation: Annotation, in ctx: CGContext) {
        guard annotation.points.count >= 2 else { return }
        let start = annotation.points.first!
        let end = annotation.points.last!

        ctx.saveGState()
        ctx.setStrokeColor(annotation.color.cgColor)
        ctx.setLineWidth(annotation.strokeWidth)
        ctx.setLineCap(.round)

        switch annotation.tool {
        case .line:
            ctx.move(to: start)
            ctx.addLine(to: end)
            ctx.strokePath()

        case .rectangle:
            let rect = CGRect(
                x: min(start.x, end.x), y: min(start.y, end.y),
                width: abs(end.x - start.x), height: abs(end.y - start.y)
            )
            ctx.stroke(rect)

        case .ellipse:
            let rect = CGRect(
                x: min(start.x, end.x), y: min(start.y, end.y),
                width: abs(end.x - start.x), height: abs(end.y - start.y)
            )
            ctx.strokeEllipse(in: rect)

        case .mosaic:
            drawMosaic(points: annotation.points, blockSize: annotation.mosaicBlockSize, in: ctx)
        }

        ctx.restoreGState()
    }

    private func drawMosaic(points: [CGPoint], blockSize: Int, in ctx: CGContext) {
        guard let image = baseImage else { return }
        let bs = CGFloat(blockSize)
        let scaleX = CGFloat(image.width) / bounds.width
        let scaleY = CGFloat(image.height) / bounds.height
        let brushRadius = currentStrokeWidth * 3

        for point in points {
            // Cover blocks around this point
            let minBX = Int((point.x - brushRadius) / bs)
            let maxBX = Int((point.x + brushRadius) / bs)
            let minBY = Int((point.y - brushRadius) / bs)
            let maxBY = Int((point.y + brushRadius) / bs)

            for bx in minBX...maxBX {
                for by in minBY...maxBY {
                    let blockRect = CGRect(x: CGFloat(bx) * bs, y: CGFloat(by) * bs, width: bs, height: bs)
                    guard bounds.intersects(blockRect) else { continue }

                    // Sample center pixel from original image
                    let centerX = Int((blockRect.midX) * scaleX)
                    let centerY = image.height - Int((blockRect.midY) * scaleY) // flip Y
                    guard centerX >= 0, centerX < image.width, centerY >= 0, centerY < image.height else { continue }

                    if let cropped = image.cropping(to: CGRect(x: centerX, y: centerY, width: 1, height: 1)),
                       let dp = cropped.dataProvider, let data = dp.data,
                       CFDataGetLength(data) >= 4 {
                        let ptr = CFDataGetBytePtr(data)!
                        let color = NSColor(
                            red: CGFloat(ptr[0]) / 255,
                            green: CGFloat(ptr[1]) / 255,
                            blue: CGFloat(ptr[2]) / 255,
                            alpha: 1.0
                        )
                        ctx.setFillColor(color.cgColor)
                        ctx.fill(blockRect)
                    }
                }
            }
        }
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point
        dragCurrent = point
        if currentTool == .mosaic {
            mosaicPoints = [point]
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragCurrent = point
        if currentTool == .mosaic {
            mosaicPoints.append(point)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let start = dragStart else { return }

        let annotation: Annotation
        if currentTool == .mosaic {
            mosaicPoints.append(point)
            annotation = Annotation(
                tool: .mosaic, points: mosaicPoints,
                color: currentColor, strokeWidth: currentStrokeWidth,
                mosaicBlockSize: mosaicBlockSize
            )
            mosaicPoints = []
        } else {
            annotation = Annotation(
                tool: currentTool, points: [start, point],
                color: currentColor, strokeWidth: currentStrokeWidth,
                mosaicBlockSize: mosaicBlockSize
            )
        }

        delegate?.canvasDidAddAnnotation(annotation)
        dragStart = nil
        dragCurrent = nil
        needsDisplay = true
    }

    /// Renders the final composite image (base + annotations)
    func renderFinalImage() -> CGImage? {
        guard let base = baseImage else { return nil }
        let size = CGSize(width: base.width, height: base.height)
        guard let ctx = CGContext(
            data: nil, width: base.width, height: base.height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Draw base image
        ctx.draw(base, in: CGRect(origin: .zero, size: size))

        // Scale annotations from view coordinates to image coordinates
        let scaleX = CGFloat(base.width) / bounds.width
        let scaleY = CGFloat(base.height) / bounds.height
        ctx.scaleBy(x: scaleX, y: scaleY)

        for annotation in annotations {
            drawAnnotation(annotation, in: ctx)
        }

        return ctx.makeImage()
    }
}
```

**Step 2: Commit**

```bash
git add -A && git commit -m "feat: add annotation canvas with CG rendering and mosaic tool"
```

---

### Task 11: Editor View with Tool Palette

**Files:**
- Create: `SuperSnip/Editor/EditorView.swift`
- Modify: `SuperSnip/Preview/CapturePreviewWindow.swift`
- Modify: `SuperSnip/App/AppDelegate.swift`

**Step 1: Create EditorView**

A SwiftUI view wrapping the AnnotationCanvas with a tool palette at the bottom.

File: `SuperSnip/Editor/EditorView.swift`

```swift
import SwiftUI
import AppKit

struct EditorToolPalette: View {
    @ObservedObject var state: AnnotationState
    let onDone: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AnnotationTool.allCases, id: \.self) { tool in
                Button {
                    state.currentTool = tool
                } label: {
                    Image(systemName: iconName(for: tool))
                        .font(.system(size: 14))
                        .frame(width: 28, height: 28)
                        .background(state.currentTool == tool ? Color.accentColor.opacity(0.3) : Color.clear)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help(tool.rawValue.capitalized)
            }

            Divider().frame(height: 20)

            ColorPicker("", selection: Binding(
                get: { Color(nsColor: state.currentColor) },
                set: { state.currentColor = NSColor($0) }
            ))
            .labelsHidden()
            .frame(width: 28, height: 28)

            Divider().frame(height: 20)

            Button { state.undo() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(!state.canUndo)

            Button { state.redo() } label: {
                Image(systemName: "arrow.uturn.forward")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(!state.canRedo)

            Divider().frame(height: 20)

            Button { onCancel() } label: {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            Button { onDone() } label: {
                Image(systemName: "checkmark")
                    .foregroundColor(.green)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func iconName(for tool: AnnotationTool) -> String {
        switch tool {
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .mosaic: return "squareshape.split.3x3"
        }
    }
}
```

**Step 2: Create Editor Window in AppDelegate**

When the user clicks "Edit" in the action toolbar, replace the preview window with an editor window that has the annotation canvas + tool palette.

Add to `AppDelegate`:

```swift
private var editorWindow: NSPanel?
private var annotationState = AnnotationState()

// In handleToolbarAction, case .edit:
case .edit:
    guard let image = capturedImage, let rect = capturedRect else { return }
    dismissPreview()
    showEditor(image: image, rect: rect)
```

```swift
private func showEditor(image: CGImage, rect: CGRect) {
    let state = AnnotationState()
    self.annotationState = state

    let canvas = AnnotationCanvas(frame: NSRect(origin: .zero, size: rect.size))
    canvas.baseImage = image
    canvas.delegate = self

    // Main editor window
    let editor = NSPanel(
        contentRect: rect,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    editor.level = .floating
    editor.isOpaque = false
    editor.backgroundColor = .clear
    editor.contentView = canvas
    editor.makeKeyAndOrderFront(nil)
    editorWindow = editor

    // Tool palette as child window
    let palette = EditorToolPalette(state: state, onDone: { [weak self] in
        self?.finishEditing()
    }, onCancel: { [weak self] in
        self?.cancelEditing()
    })
    let hostingView = NSHostingView(rootView: palette)
    hostingView.frame.size = hostingView.fittingSize

    let paletteRect = CGRect(
        x: rect.midX - hostingView.frame.width / 2,
        y: rect.origin.y - hostingView.frame.height - 8,
        width: hostingView.frame.width,
        height: hostingView.frame.height
    )
    let paletteWindow = NSPanel(
        contentRect: paletteRect,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    paletteWindow.level = .floating
    paletteWindow.isOpaque = false
    paletteWindow.backgroundColor = .clear
    paletteWindow.contentView = hostingView
    editor.addChildWindow(paletteWindow, ordered: .above)

    // Sync state changes to canvas
    state.$currentTool.assign(to: \.currentTool, on: canvas).store(in: &cancellables)
    state.$currentColor.assign(to: \.currentColor, on: canvas).store(in: &cancellables)
    state.$currentStrokeWidth.assign(to: \.currentStrokeWidth, on: canvas).store(in: &cancellables)
    state.$annotations.assign(to: \.annotations, on: canvas).store(in: &cancellables)
}

private var cancellables = Set<AnyCancellable>()

private func finishEditing() {
    guard let canvas = editorWindow?.contentView as? AnnotationCanvas,
          let finalImage = canvas.renderFinalImage() else { return }
    ClipboardManager.copyToClipboard(finalImage)
    editorWindow?.orderOut(nil)
    editorWindow = nil
}

private func cancelEditing() {
    editorWindow?.orderOut(nil)
    editorWindow = nil
}
```

Add Combine import to AppDelegate:

```swift
import Combine
```

**Step 3: Implement AnnotationCanvasDelegate in AppDelegate**

```swift
extension AppDelegate: AnnotationCanvasDelegate {
    func canvasDidAddAnnotation(_ annotation: Annotation) {
        annotationState.addAnnotation(annotation)
    }
}
```

**Step 4: Build and test**

Expected: Capture → Edit → canvas appears with base image → tool palette below → select line tool, drag to draw red line → switch to rectangle, drag to draw rectangle → mosaic brush pixelates areas → undo/redo work → checkmark copies final image to clipboard → X cancels.

**Step 5: Commit**

```bash
git add -A && git commit -m "feat: add editor view with tool palette and annotation tools"
```

---

### Task 12: Scrolling Capture - Frame Collector

**Files:**
- Create: `SuperSnip/ScrollCapture/ScrollCaptureManager.swift`

**Step 1: Create ScrollCaptureManager**

Monitors scroll events within a region and captures frames after each scroll. Uses a debounce timer to wait for the screen to settle before capturing.

File: `SuperSnip/ScrollCapture/ScrollCaptureManager.swift`

```swift
import AppKit

final class ScrollCaptureManager {
    private var captureRect: CGRect // AppKit screen coordinates
    private var frames: [CGImage] = []
    private var scrollMonitor: Any?
    private var debounceTimer: Timer?
    private var onComplete: (([CGImage]) -> Void)?
    private var onFrameAdded: ((Int) -> Void)?

    init(rect: CGRect) {
        self.captureRect = rect
    }

    func start(onFrameAdded: @escaping (Int) -> Void, onComplete: @escaping ([CGImage]) -> Void) {
        self.onComplete = onComplete
        self.onFrameAdded = onFrameAdded
        frames = []

        // Capture initial frame
        if let initial = ScreenCaptureManager.capture(rect: captureRect) {
            frames.append(initial)
            onFrameAdded(frames.count)
        }

        // Monitor scroll events
        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScroll(event)
        }
    }

    func stop() {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
        debounceTimer?.invalidate()
        onComplete?(frames)
    }

    private func handleScroll(_ event: NSEvent) {
        // Only care about scrolls in our capture area
        let mouseLocation = NSEvent.mouseLocation
        guard captureRect.contains(mouseLocation) else { return }

        // Debounce: wait 200ms after last scroll to capture
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            self?.captureFrame()
        }
    }

    private func captureFrame() {
        guard let image = ScreenCaptureManager.capture(rect: captureRect) else { return }
        frames.append(image)
        onFrameAdded?(frames.count)
    }
}
```

**Step 2: Commit**

```bash
git add -A && git commit -m "feat: add scroll capture frame collector with debounce"
```

---

### Task 13: Scrolling Capture - Image Stitcher

**Files:**
- Create: `SuperSnip/ScrollCapture/ImageStitcher.swift`

**Step 1: Create ImageStitcher**

Detects overlapping regions between consecutive frames using pixel comparison, then stitches them into one tall image.

File: `SuperSnip/ScrollCapture/ImageStitcher.swift`

```swift
import CoreGraphics
import AppKit

final class ImageStitcher {

    /// Stitch an array of overlapping frames into a single tall image.
    static func stitch(frames: [CGImage]) -> CGImage? {
        guard frames.count >= 2 else { return frames.first }

        var result = frames[0]
        for i in 1..<frames.count {
            guard let merged = stitchTwo(top: result, bottom: frames[i]) else { continue }
            result = merged
        }
        return result
    }

    /// Stitch two vertically overlapping images.
    /// `top` is the accumulated image, `bottom` is the new frame.
    /// We find how many rows at the bottom of `top` overlap with the top of `bottom`.
    private static func stitchTwo(top: CGImage, bottom: CGImage) -> CGImage? {
        guard top.width == bottom.width else { return nil }
        let width = top.width

        // Get pixel data for both images
        guard let topData = pixelData(for: top),
              let bottomData = pixelData(for: bottom) else { return nil }

        let topHeight = top.height
        let bottomHeight = bottom.height
        let bytesPerRow = width * 4

        // Search for overlap: compare bottom rows of `top` with top rows of `bottom`
        // Search range: 10% to 90% of bottom image height
        let minOverlap = max(10, bottomHeight / 10)
        let maxOverlap = bottomHeight * 9 / 10

        var bestOverlap = 0
        var bestScore = Double.infinity

        for overlap in minOverlap..<maxOverlap {
            let score = rowSimilarity(
                topData: topData, topRow: topHeight - overlap,
                bottomData: bottomData, bottomRow: 0,
                width: width, rowCount: min(overlap, 5) // compare first 5 rows of overlap
            )
            if score < bestScore {
                bestScore = score
                bestOverlap = overlap
            }
        }

        // Threshold: if best score is too high, no good overlap found
        guard bestScore < 30.0 else {
            // Just concatenate without overlap removal
            return concatenate(top: top, bottom: bottom, overlap: 0)
        }

        return concatenate(top: top, bottom: bottom, overlap: bestOverlap)
    }

    /// Compare `rowCount` rows starting at `topRow` in topData and `bottomRow` in bottomData.
    /// Returns mean absolute difference per pixel component.
    private static func rowSimilarity(
        topData: Data, topRow: Int,
        bottomData: Data, bottomRow: Int,
        width: Int, rowCount: Int
    ) -> Double {
        let bytesPerRow = width * 4
        var totalDiff: Int = 0
        var count = 0

        for r in 0..<rowCount {
            let topOffset = (topRow + r) * bytesPerRow
            let bottomOffset = (bottomRow + r) * bytesPerRow
            guard topOffset + bytesPerRow <= topData.count,
                  bottomOffset + bytesPerRow <= bottomData.count else { continue }

            for x in stride(from: 0, to: bytesPerRow, by: 4) {
                totalDiff += abs(Int(topData[topOffset + x]) - Int(bottomData[bottomOffset + x]))     // R
                totalDiff += abs(Int(topData[topOffset + x + 1]) - Int(bottomData[bottomOffset + x + 1])) // G
                totalDiff += abs(Int(topData[topOffset + x + 2]) - Int(bottomData[bottomOffset + x + 2])) // B
                count += 3
            }
        }
        return count > 0 ? Double(totalDiff) / Double(count) : Double.infinity
    }

    /// Vertically concatenate two images, removing `overlap` rows from bottom of `top`.
    private static func concatenate(top: CGImage, bottom: CGImage, overlap: Int) -> CGImage? {
        let width = top.width
        let newHeight = top.height + bottom.height - overlap

        guard let ctx = CGContext(
            data: nil, width: width, height: newHeight,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Draw top image at the top (CG origin is bottom-left, so "top" image goes at y offset)
        let bottomImageHeight = bottom.height
        ctx.draw(top, in: CGRect(x: 0, y: bottomImageHeight - overlap, width: width, height: top.height))
        ctx.draw(bottom, in: CGRect(x: 0, y: 0, width: width, height: bottomImageHeight))

        return ctx.makeImage()
    }

    /// Extract raw pixel data from a CGImage.
    private static func pixelData(for image: CGImage) -> Data? {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4

        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = ctx.data else { return nil }
        return Data(bytes: data, count: height * bytesPerRow)
    }
}
```

**Step 2: Commit**

```bash
git add -A && git commit -m "feat: add image stitcher with overlap detection for scrolling capture"
```

---

### Task 14: Wire Scrolling Capture into UI

**Files:**
- Modify: `SuperSnip/Preview/ActionToolbar.swift` — add "Scroll Capture" button
- Modify: `SuperSnip/App/AppDelegate.swift` — add scroll capture flow

**Step 1: Add scroll capture action to ToolbarAction**

```swift
enum ToolbarAction {
    case copy, save, edit, pin, cancel, scrollCapture
}
```

Add button in `ActionToolbar`:

```swift
toolbarButton(icon: "arrow.up.and.down.text.horizontal", tooltip: "Scroll Capture", action: .scrollCapture)
```

**Step 2: Implement scroll capture flow in AppDelegate**

```swift
private var scrollCaptureManager: ScrollCaptureManager?

// In handleToolbarAction:
case .scrollCapture:
    guard let rect = capturedRect else { return }
    dismissPreview()
    startScrollCapture(rect: rect)

private func startScrollCapture(rect: CGRect) {
    let manager = ScrollCaptureManager(rect: rect)
    scrollCaptureManager = manager

    // Show a small floating indicator with frame count and stop button
    // For now, just use console output and stop via hotkey
    manager.start(
        onFrameAdded: { count in
            print("Scroll capture: \(count) frames")
        },
        onComplete: { [weak self] frames in
            guard let stitched = ImageStitcher.stitch(frames: frames) else { return }
            ClipboardManager.copyToClipboard(stitched)
            print("Scroll capture complete: \(stitched.width)x\(stitched.height)")
            self?.scrollCaptureManager = nil
        }
    )

    // Stop after double-press ESC or via menu — for MVP, use a timer or secondary hotkey
    // Register a local monitor for ESC to stop
    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        if event.keyCode == 53 { // ESC
            self?.scrollCaptureManager?.stop()
            return nil
        }
        return event
    }
}
```

**Step 3: Build and test**

Expected: Capture area → Scroll Capture → scroll within the region → console shows frame count increasing → press ESC → frames stitched → long image copied to clipboard.

**Step 4: Commit**

```bash
git add -A && git commit -m "feat: wire scrolling capture into UI with ESC to stop"
```

---

### Task 15: Polish and Integration Testing

**Files:**
- All files — bug fixes and polish

**Step 1: Handle multi-monitor correctly**

Verify overlay covers all screens. Test that coordinate conversion works for non-primary displays.

**Step 2: Handle screen recording permission**

Add a check on launch:

```swift
// In AppDelegate.applicationDidFinishLaunching
if !CGPreflightScreenCaptureAccess() {
    CGRequestScreenCaptureAccess()
}
```

**Step 3: Add keyboard shortcuts in editor**

- Cmd+Z → undo
- Cmd+Shift+Z → redo
- Cmd+C → copy and close editor
- ESC → cancel editor

**Step 4: Improve overlay — make selected region transparent**

In `SelectionView.draw`, use a clipping path so the selected region shows the actual screen content (not the dark tint):

```swift
// Draw dark overlay with a hole for the selection
NSColor.black.withAlphaComponent(0.3).setFill()
let fullPath = NSBezierPath(rect: bounds)
if let sel = selectionRect {
    fullPath.append(NSBezierPath(rect: sel).reversed)
}
fullPath.fill()
```

**Step 5: Final commit**

```bash
git add -A && git commit -m "feat: polish multi-monitor, permissions, keyboard shortcuts"
```

---

## Summary of Implementation Order

| Task | Component | Description |
|------|-----------|-------------|
| 1 | Project Setup | Xcode project, Menu Bar app, Package.swift |
| 2 | Global Hotkey | Carbon RegisterEventHotKey |
| 3 | Overlay Window | Full-screen transparent NSPanel |
| 4 | Region Selection | Mouse drag, dimension label, ESC |
| 5 | Screen Capture | CGWindowListCreateImage |
| 6 | Utilities | Clipboard + save-to-file |
| 7 | Preview Window | In-place screenshot + action toolbar |
| 8 | Pin Window | Always-on-top floating screenshot |
| 9 | Annotation Model | Data types + undo/redo stack |
| 10 | Annotation Canvas | Core Graphics rendering + mouse events |
| 11 | Editor View | Tool palette + editor window |
| 12 | Scroll Capture | Frame collector with scroll monitoring |
| 13 | Image Stitcher | Pixel overlap detection + stitch |
| 14 | Scroll Capture UI | Wire into toolbar + ESC to stop |
| 15 | Polish | Multi-monitor, permissions, shortcuts |
