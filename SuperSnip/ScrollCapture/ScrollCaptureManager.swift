import AppKit

final class ScrollCaptureManager {
    private let captureRect: CGRect // AppKit screen coordinates
    private var frames: [CGImage] = []
    private var timerSource: DispatchSourceTimer?
    private var onFrameAdded: ((Int) -> Void)?
    private var onComplete: (([CGImage]) -> Void)?
    private var isStopped = false

    private let captureInterval: TimeInterval = 0.3
    private let maxFrames = 100
    private let captureQueue = DispatchQueue(label: "com.supersnip.scroll-capture", qos: .userInitiated)

    init(rect: CGRect) {
        self.captureRect = rect
    }

    func start(onFrameAdded: @escaping (Int) -> Void, onComplete: @escaping ([CGImage]) -> Void) {
        self.onFrameAdded = onFrameAdded
        self.onComplete = onComplete
        frames = []
        isStopped = false

        // Capture initial frame on background queue
        captureQueue.async { [weak self] in
            self?.captureFrame()
        }

        let timer = DispatchSource.makeTimerSource(queue: captureQueue)
        timer.schedule(deadline: .now() + captureInterval, repeating: captureInterval)
        timer.setEventHandler { [weak self] in
            self?.captureFrame()
        }
        timer.resume()
        timerSource = timer
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true

        timerSource?.cancel()
        timerSource = nil

        // Capture one final frame, then deliver results
        captureQueue.async { [self] in
            if let image = ScreenCaptureManager.capture(rect: captureRect) {
                if let lastFrame = frames.last, !framesAreNearlyIdentical(lastFrame, image) {
                    frames.append(image)
                } else if frames.isEmpty {
                    frames.append(image)
                }
            }
            let capturedFrames = frames
            DispatchQueue.main.async { [weak self] in
                self?.onComplete?(capturedFrames)
                self?.onFrameAdded = nil
                self?.onComplete = nil
            }
        }
    }

    /// Called on captureQueue
    private func captureFrame() {
        guard !isStopped else { return }
        guard let image = ScreenCaptureManager.capture(rect: captureRect) else { return }

        // Skip if this frame is nearly identical to the last one (no scroll happened)
        if let lastFrame = frames.last, framesAreNearlyIdentical(lastFrame, image) {
            return
        }

        frames.append(image)
        let count = frames.count

        DispatchQueue.main.async { [weak self] in
            self?.onFrameAdded?(count)
        }

        if count >= maxFrames {
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
        ctx.draw(image, in: CGRect(x: 0, y: -row, width: image.width, height: image.height))
        guard let data = ctx.data else { return nil }
        return Data(bytes: data, count: bytesPerRow)
    }
}
