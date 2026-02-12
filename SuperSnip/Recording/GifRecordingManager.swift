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

    /// Called on captureQueue. Captures at full resolution with cursor.
    private func captureFrame(maxFrames: Int) {
        guard !isStopped else { return }
        guard let image = ScreenCaptureManager.capture(rect: captureRect, includeCursor: true) else { return }

        frames.append(image)
        let count = frames.count

        DispatchQueue.main.async { [weak self] in
            self?.onFrameAdded?(count)
        }

        if count >= maxFrames {
            stop()
        }
    }

}
