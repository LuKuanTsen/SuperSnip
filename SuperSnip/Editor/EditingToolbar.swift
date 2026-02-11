import SwiftUI
import AppKit

enum CanvasEditMode {
    case draw
    case mosaic
}

enum BrushSize: CGFloat, CaseIterable {
    case small = 8
    case medium = 16
    case large = 32

    var label: String {
        switch self {
        case .small: return "S"
        case .medium: return "M"
        case .large: return "L"
        }
    }
}

enum EditingAction {
    case setBrushSize(BrushSize)
    case setColor(NSColor)
    case undo
    case done
    case cancel
}

struct EditingToolbar: View {
    let mode: CanvasEditMode
    let initialBrushSize: BrushSize
    let initialColor: NSColor
    @State private var activeBrushSize: BrushSize = .medium
    @State private var activeColor: NSColor = .systemRed
    let onAction: (EditingAction) -> Void

    init(mode: CanvasEditMode, brushSize: BrushSize = .medium, color: NSColor = .systemRed, onAction: @escaping (EditingAction) -> Void) {
        self.mode = mode
        self.initialBrushSize = brushSize
        self.initialColor = color
        self._activeBrushSize = State(initialValue: brushSize)
        self._activeColor = State(initialValue: color)
        self.onAction = onAction
    }

    private let drawColors: [(NSColor, String)] = [
        (.systemRed, "Red"),
        (.systemGreen, "Green"),
        (.systemBlue, "Blue"),
        (.systemYellow, "Yellow"),
        (.white, "White"),
        (.black, "Black"),
    ]

    var body: some View {
        HStack(spacing: 2) {
            // Mode indicator
            Image(systemName: mode == .draw ? "pencil.tip" : "square.grid.3x3")
                .font(.system(size: 14))
                .frame(width: 28, height: 28)

            Divider().frame(height: 20)

            // Brush sizes
            ForEach(BrushSize.allCases, id: \.rawValue) { size in
                Button {
                    activeBrushSize = size
                    onAction(.setBrushSize(size))
                } label: {
                    Text(size.label)
                        .font(.system(size: 12, weight: activeBrushSize == size ? .bold : .regular))
                        .frame(width: 28, height: 28)
                        .background(
                            activeBrushSize == size
                                ? Color.white.opacity(0.2)
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }

            // Color palette (draw mode only)
            if mode == .draw {
                Divider().frame(height: 20)

                ForEach(drawColors, id: \.1) { color, name in
                    Button {
                        activeColor = color
                        onAction(.setColor(color))
                    } label: {
                        Circle()
                            .fill(Color(nsColor: color))
                            .frame(width: 16, height: 16)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        Color.white,
                                        lineWidth: activeColor == color ? 2 : 0
                                    )
                            )
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help(name)
                }
            }

            Divider().frame(height: 20)

            // Undo
            Button {
                onAction(.undo)
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Undo last stroke")

            Divider().frame(height: 20)

            // Done
            Button {
                onAction(.done)
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 14))
                    .foregroundStyle(.green)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Apply edits")

            // Cancel
            Button {
                onAction(.cancel)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14))
                    .foregroundStyle(.red)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Discard edits")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
