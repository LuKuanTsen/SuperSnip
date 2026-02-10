import SwiftUI

enum ToolbarAction {
    case copy
    case save
    case edit
    case pin
    case cancel
    case scrollCapture
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

            toolbarButton(icon: "pencil.and.outline", tooltip: "Edit", action: .edit)
            toolbarButton(icon: "arrow.up.and.down.text.horizontal", tooltip: "Scroll Capture", action: .scrollCapture)

            Divider().frame(height: 20)

            toolbarButton(icon: "xmark", tooltip: "Cancel", action: .cancel)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
