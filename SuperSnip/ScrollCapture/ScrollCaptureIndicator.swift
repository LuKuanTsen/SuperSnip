import AppKit
import SwiftUI

/// A small floating indicator that shows frame count and a stop button during scroll capture.
final class ScrollCaptureIndicator {
    private var window: NSPanel?
    private let state = IndicatorState()

    func show(below rect: CGRect) {
        let hostingView = NSHostingView(rootView: IndicatorView(state: state))
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

    func updateFrameCount(_ count: Int) {
        DispatchQueue.main.async {
            self.state.frameCount = count
        }
    }

    var onStop: (() -> Void)? {
        get { state.onStop }
        set { state.onStop = newValue }
    }

    func dismiss() {
        window?.orderOut(nil)
        window = nil
    }
}

private class IndicatorState: ObservableObject {
    @Published var frameCount: Int = 0
    var onStop: (() -> Void)?
}

private struct IndicatorView: View {
    @ObservedObject var state: IndicatorState

    var body: some View {
        HStack(spacing: 8) {
            // Pulsing red dot
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)

            Text("Scroll Capture")
                .font(.system(size: 12, weight: .medium))

            Text("\(state.frameCount) frames")
                .font(.system(size: 12).monospacedDigit())
                .foregroundColor(.secondary)

            Button {
                state.onStop?()
            } label: {
                Text("Done")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
