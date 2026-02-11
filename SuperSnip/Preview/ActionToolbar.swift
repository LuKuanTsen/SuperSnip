import SwiftUI

enum ToolbarAction {
    case copy
    case save
    case pin
    case cancel
    case scrollCapture
    case scrollCaptureDebug
    case recordGif
    case draw
    case mosaic
    case undo
    case redo
}

class EditHistoryState: ObservableObject {
    @Published var canUndo = false
    @Published var canRedo = false
}

struct ActionToolbar: View {
    @ObservedObject var historyState: EditHistoryState
    let onAction: (ToolbarAction) -> Void

    init(historyState: EditHistoryState = EditHistoryState(), onAction: @escaping (ToolbarAction) -> Void) {
        self.historyState = historyState
        self.onAction = onAction
    }

    var body: some View {
        HStack(spacing: 2) {
            toolbarButton(icon: "pin", tooltip: "Pin to screen", action: .pin)

            Divider().frame(height: 20)

            toolbarButton(icon: "square.and.arrow.down", tooltip: "Save", action: .save)
            toolbarButton(icon: "doc.on.doc", tooltip: "Copy to clipboard", action: .copy)

            Divider().frame(height: 20)

            toolbarButton(icon: "pencil.tip", tooltip: "Draw", action: .draw)
            toolbarButton(icon: "square.grid.3x3", tooltip: "Mosaic", action: .mosaic)

            if historyState.canUndo || historyState.canRedo {
                Divider().frame(height: 20)

                Button {
                    onAction(.undo)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 14))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                        .opacity(historyState.canUndo ? 1 : 0.3)
                }
                .buttonStyle(.plain)
                .disabled(!historyState.canUndo)
                .help("Undo")

                Button {
                    onAction(.redo)
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 14))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                        .opacity(historyState.canRedo ? 1 : 0.3)
                }
                .buttonStyle(.plain)
                .disabled(!historyState.canRedo)
                .help("Redo")
            }

            Divider().frame(height: 20)

            toolbarButton(icon: "record.circle", tooltip: "Record GIF", action: .recordGif)
            scrollCaptureButton()

            Divider().frame(height: 20)

            toolbarButton(icon: "xmark", tooltip: "Cancel", action: .cancel)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func scrollCaptureButton() -> some View {
        Image(systemName: "arrow.up.and.down.text.horizontal")
            .font(.system(size: 14))
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .onTapGesture {
                onAction(.scrollCapture)
            }
            .contextMenu {
                Button("Debug Mode") {
                    onAction(.scrollCaptureDebug)
                }
            }
            .help("Scroll Capture (right-click for debug)")
    }

    private func toolbarButton(icon: String, tooltip: String, action: ToolbarAction) -> some View {
        Button {
            onAction(action)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}
