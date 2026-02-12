import AppKit
import SwiftUI

final class RecordingIndicator {
    private var window: NSPanel?
    private let state = RecordingIndicatorState()
    private var countdownTimer: Timer?

    func show(below rect: CGRect) {
        let hostingView = NSHostingView(rootView: RecordingIndicatorView(state: state))
        hostingView.frame.size = hostingView.fittingSize

        let indicatorRect = CGRect(
            x: rect.midX - hostingView.frame.width / 2,
            y: rect.origin.y - hostingView.frame.height - 12,
            width: hostingView.frame.width,
            height: hostingView.frame.height
        )

        let panel = NSPanel(
            contentRect: indicatorRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.contentView = hostingView
        panel.makeKeyAndOrderFront(nil)
        window = panel
    }

    /// Start a countdown, then call onReady when done.
    func startCountdown(seconds: Int = 3, onReady: @escaping () -> Void) {
        state.countdownRemaining = seconds
        state.isCountingDown = true

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.state.countdownRemaining -= 1
            if self.state.countdownRemaining <= 0 {
                timer.invalidate()
                self.countdownTimer = nil
                self.state.isCountingDown = false
                onReady()
            }
        }
    }

    func updateFrameCount(_ count: Int) {
        DispatchQueue.main.async {
            self.state.frameCount = count
        }
    }

    func updateElapsedTime(_ seconds: Double) {
        DispatchQueue.main.async {
            self.state.elapsedSeconds = seconds
        }
    }

    var onStop: (() -> Void)? {
        get { state.onStop }
        set { state.onStop = newValue }
    }

    func dismiss() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        window?.orderOut(nil)
        window = nil
    }
}

private class RecordingIndicatorState: ObservableObject {
    @Published var frameCount: Int = 0
    @Published var elapsedSeconds: Double = 0
    @Published var isCountingDown: Bool = false
    @Published var countdownRemaining: Int = 0
    var onStop: (() -> Void)?
}

private struct RecordingIndicatorView: View {
    @ObservedObject var state: RecordingIndicatorState

    var body: some View {
        HStack(spacing: 8) {
            if state.isCountingDown {
                // Countdown mode
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)

                Text("\(state.countdownRemaining)")
                    .font(.system(size: 20, weight: .bold).monospacedDigit())
                    .foregroundColor(.primary)
                    .frame(minWidth: 24)
            } else {
                // Recording mode
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .opacity(pulseOpacity)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulseOpacity)

                Text("Recording")
                    .font(.system(size: 12, weight: .medium))

                Text("\(state.frameCount) frames")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundColor(.secondary)

                Text(formattedTime)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundColor(.secondary)

                Button {
                    state.onStop?()
                } label: {
                    Text("Done")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)

                Text("ESC")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.secondary.opacity(0.5), lineWidth: 0.5)
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minWidth: 320)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var pulseOpacity: Double {
        state.frameCount > 0 ? 0.3 : 1.0
    }

    private var formattedTime: String {
        let s = Int(state.elapsedSeconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
