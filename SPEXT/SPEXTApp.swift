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
            Image(appState.menuBarIcon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(appState.menuBarColor)
                .opacity(appState.isRecording || appState.isTranscribing ? 0.45 : 1)
                .animation(
                    appState.isRecording || appState.isTranscribing
                        ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                        : .default,
                    value: appState.isRecording || appState.isTranscribing
                )
        }
        .menuBarExtraStyle(.window)

        // ── Settings Window ─────────────────────────────────────
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
