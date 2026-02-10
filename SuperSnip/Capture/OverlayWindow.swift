import AppKit

final class OverlayWindow: NSPanel {
    init() {
        let fullFrame = NSScreen.screens.reduce(CGRect.zero) { $0.union($1.frame) }

        super.init(
            contentRect: fullFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let selectionView = SelectionView(frame: fullFrame)
        selectionView.autoresizingMask = [.width, .height]
        self.contentView = selectionView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func setSelectionDelegate(_ delegate: SelectionViewDelegate) {
        (contentView as? SelectionView)?.delegate = delegate
    }
}
