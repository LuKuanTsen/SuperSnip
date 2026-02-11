import SwiftUI

enum ToolbarAction {
    case copy
    case save
    case pin
    case cancel
    case scrollCapture
    case scrollCaptureDebug
}

struct ActionToolbar: View {
    let onAction: (ToolbarAction) -> Void

    var body: some View {
        HStack(spacing: 2) {
            toolbarButton(icon: "pin", tooltip: "Pin to screen", action: .pin)

            Divider().frame(height: 20)

            toolbarButton(icon: "square.and.arrow.down", tooltip: "Save", action: .save)
            toolbarButton(icon: "doc.on.doc", tooltip: "Copy to clipboard", action: .copy)

            Divider().frame(height: 20)

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
