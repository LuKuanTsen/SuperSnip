import SwiftUI

@main
struct SuperSnipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Super Snip", systemImage: "scissors") {
            Button("Capture Area") {
                appDelegate.startCapture()
            }
            .keyboardShortcut("4", modifiers: [.command, .shift])
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
