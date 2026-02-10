import AppKit

final class ScrollCaptureManager {
    private let captureRect: CGRect // AppKit screen coordinates
    private var frames: [CGImage] = []
    private var scrollMonitor: Any?
    private var debounceTimer: Timer?
    private var onFrameAdded: ((Int) -> Void)?
    private var onComplete: (([CGImage]) -> Void)?
    private var lastFrameTime: Date = .distantPast

    // Minimum interval between captures to avoid near-duplicate frames
    private let minCaptureInterval: TimeInterval = 0.3
    // Debounce delay: wait for scrolling to stop before capturing
    private let debounceDelay: TimeInterval = 0.2

    init(rect: CGRect) {
        self.captureRect = rect
    }

    func start(onFrameAdded: @escaping (Int) -> Void, onComplete: @escaping ([CGImage]) -> Void) {
        self.onFrameAdded = onFrameAdded
        self.onComplete = onComplete
        frames = []

        // Capture initial frame
        captureFrame()

        // Monitor scroll events globally
        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScroll(event)
        }

        // Also monitor locally in case our app's windows receive the events
        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScroll(event)
            return event
        }
        // Store local monitor too — use scrollMonitor as a tuple isn't clean, so store separately
        _localMonitor = localMonitor
    }

    private var _localMonitor: Any?

    func stop() {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
        if let monitor = _localMonitor {
            NSEvent.removeMonitor(monitor)
            _localMonitor = nil
        }
        debounceTimer?.invalidate()
        debounceTimer = nil

        // Capture one final frame in case the last scroll wasn't captured
        captureFrame()

        onComplete?(frames)
        onFrameAdded = nil
        onComplete = nil
    }

    private func handleScroll(_ event: NSEvent) {
        // Only care about vertical scrolls
        guard abs(event.scrollingDeltaY) > 0.5 else { return }

        // Check if mouse is within our capture area
        let mouseLocation = NSEvent.mouseLocation
        // Expand the check area slightly to account for scrollbar interactions
        let expandedRect = captureRect.insetBy(dx: -20, dy: -20)
        guard expandedRect.contains(mouseLocation) else { return }

        // Debounce: wait for scrolling to settle
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceDelay, repeats: false) { [weak self] _ in
            self?.captureFrame()
        }
    }

    private func captureFrame() {
        // Rate limit captures
        let now = Date()
        guard now.timeIntervalSince(lastFrameTime) >= minCaptureInterval else { return }

        guard let image = ScreenCaptureManager.capture(rect: captureRect) else { return }

        // Skip if this frame is nearly identical to the last one (no scroll happened)
        if let lastFrame = frames.last, framesAreNearlyIdentical(lastFrame, image) {
            return
        }

        frames.append(image)
        lastFrameTime = now
        onFrameAdded?(frames.count)
    }

    /// Quick check: compare a few sample rows to see if two frames are nearly identical.
    private func framesAreNearlyIdentical(_ a: CGImage, _ b: CGImage) -> Bool {
        guard a.width == b.width, a.height == b.height else { return false }
        guard let dataA = pixelRow(of: a, row: a.height / 2),
              let dataB = pixelRow(of: b, row: b.height / 2) else { return false }

        var diff: Int = 0
        let count = min(dataA.count, dataB.count)
        let sampleStep = max(1, count / 200) // Sample ~200 pixels
        var samples = 0
        for i in stride(from: 0, to: count, by: sampleStep) {
            diff += abs(Int(dataA[i]) - Int(dataB[i]))
            samples += 1
        }
        let avgDiff = samples > 0 ? Double(diff) / Double(samples) : 0
        return avgDiff < 3.0 // Nearly identical
    }

    private func pixelRow(of image: CGImage, row: Int) -> Data? {
        let width = image.width
        let bytesPerRow = width * 4
        guard let ctx = CGContext(
            data: nil, width: width, height: 1,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        // Draw just the one row we want
        ctx.draw(image, in: CGRect(x: 0, y: -row, width: image.width, height: image.height))
        guard let data = ctx.data else { return nil }
        return Data(bytes: data, count: bytesPerRow)
    }
}
