import AppKit

final class GifRecordingManager {
    private let captureRect: CGRect
    private var frames: [CGImage] = []
    private var timerSource: DispatchSourceTimer?
    private var onFrameAdded: ((Int) -> Void)?
    private var onComplete: (([CGImage]) -> Void)?
    private var isStopped = false

    private let fps: Double = 8
    private let maxDuration: Double = 30 // seconds
    private let captureQueue = DispatchQueue(label: "com.supersnip.gif-capture", qos: .userInitiated)

    var frameDelay: Double { 1.0 / fps }

    init(rect: CGRect) {
        self.captureRect = rect
    }

    func start(onFrameAdded: @escaping (Int) -> Void, onComplete: @escaping ([CGImage]) -> Void) {
        self.onFrameAdded = onFrameAdded
        self.onComplete = onComplete
        frames = []
        isStopped = false

        let interval = frameDelay
        let maxFrames = Int(maxDuration * fps)

        // Capture initial frame
        captureQueue.async { [weak self] in
            self?.captureFrame(maxFrames: maxFrames)
        }

        let timer = DispatchSource.makeTimerSource(queue: captureQueue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.captureFrame(maxFrames: maxFrames)
        }
        timer.resume()
        timerSource = timer
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true

        timerSource?.cancel()
        timerSource = nil

        let capturedFrames = frames
        DispatchQueue.main.async { [weak self] in
            self?.onComplete?(capturedFrames)
            self?.onFrameAdded = nil
            self?.onComplete = nil
        }
    }

    /// Called on captureQueue. Captures and downscales to 1x for smaller GIF.
    private func captureFrame(maxFrames: Int) {
        guard !isStopped else { return }
        guard let image = ScreenCaptureManager.capture(rect: captureRect) else { return }

        // Downscale Retina (2x) capture to 1x point size for smaller GIF
        let scaled = downscale(image)
        frames.append(scaled)
        let count = frames.count

        DispatchQueue.main.async { [weak self] in
            self?.onFrameAdded?(count)
        }

        if count >= maxFrames {
            stop()
        }
    }

    /// Downscale to 1x point size (half the pixel dimensions on Retina).
    private func downscale(_ image: CGImage) -> CGImage {
        let targetWidth = image.width / 2
        let targetHeight = image.height / 2
        guard targetWidth > 0, targetHeight > 0 else { return image }

        guard let ctx = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return ctx.makeImage() ?? image
    }
}
