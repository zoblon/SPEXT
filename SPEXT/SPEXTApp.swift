import SwiftUI

@main
struct SPEXTApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        // ── Menu Bar Icon + Popover ──────────────────────────────
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Image(systemName: appState.menuBarIcon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(appState.menuBarColor)
                .symbolEffect(.pulse, isActive: appState.isRecording || appState.isTranscribing)
        }
        .menuBarExtraStyle(.window)

        // ── Settings Window ─────────────────────────────────────
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
