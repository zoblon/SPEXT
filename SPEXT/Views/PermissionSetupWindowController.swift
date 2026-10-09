import AppKit
import SwiftUI

final class PermissionSetupWindowController {
    private weak var appState: AppState?
    private var window: NSWindow?

    init(appState: AppState) {
        self.appState = appState
    }

    func show() {
        guard let appState else { return }

        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = PermissionSetupView { [weak self] in
            self?.close()
        }
        .environmentObject(appState)

        let hostingView = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "SPEXT einrichten"
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
        window = nil
    }
}
