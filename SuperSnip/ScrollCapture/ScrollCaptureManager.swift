import AppKit

final class ScrollCaptureManager {
    private let captureRect: CGRect // AppKit screen coordinates
    private var frames: [CGImage] = []
    private var captureTimer: Timer?
    private var onFrameAdded: ((Int) -> Void)?
    private var onComplete: (([CGImage]) -> Void)?

    private let captureInterval: TimeInterval = 0.3
    private let maxFrames = 100

    init(rect: CGRect) {
        self.captureRect = rect
    }

    func start(onFrameAdded: @escaping (Int) -> Void, onComplete: @escaping ([CGImage]) -> Void) {
        self.onFrameAdded = onFrameAdded
        self.onComplete = onComplete
        frames = []

        // Capture initial frame
        captureFrame()

        // Periodically capture frames — duplicate detection skips identical frames
        captureTimer = Timer.scheduledTimer(withTimeInterval: captureInterval, repeats: true) { [weak self] _ in
            self?.captureFrame()
        }
    }

    func stop() {
        captureTimer?.invalidate()
        captureTimer = nil

        // Capture one final frame
        captureFrame()

        onComplete?(frames)
        onFrameAdded = nil
        onComplete = nil
    }

    private func captureFrame() {
        guard let image = ScreenCaptureManager.capture(rect: captureRect) else { return }

        // Skip if this frame is nearly identical to the last one (no scroll happened)
        if let lastFrame = frames.last, framesAreNearlyIdentical(lastFrame, image) {
            return
        }

        frames.append(image)
        onFrameAdded?(frames.count)

        if frames.count >= maxFrames {
            stop()
        }
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
