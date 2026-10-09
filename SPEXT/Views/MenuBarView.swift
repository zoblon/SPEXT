import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──────────────────────────────────────────
            HStack {
                Text("SPEXT")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Image(systemName: "gearshape")
                        .imageScale(.medium)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            // ── Status Badge ─────────────────────────────────────
            HStack(spacing: 8) {
                Circle()
                    .fill(appState.statusColor)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(appState.statusColor.opacity(0.4), lineWidth: 3)
                            .scaleEffect(appState.isRecording ? 2.0 : 1.0)
                            .opacity(appState.isRecording ? 0 : 1)
                            .animation(
                                appState.isRecording
                                    ? .easeOut(duration: 0.9).repeatForever(autoreverses: false)
                                    : .default,
                                value: appState.isRecording
                            )
                    )

                Text(appState.statusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                if appState.isRecording || appState.isTranscribing {
                    let modeColor: Color = appState.currentMode == .polish ? .blue : .red
                    let modeLabel: LocalizedStringKey = appState.currentMode == .polish ? "Message" : "Direct"
                    Text(modeLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(modeColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(modeColor.opacity(0.12)))
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: appState.isRecording)
            .animation(.easeInOut(duration: 0.2), value: appState.isTranscribing)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // ── Last Transcription ────────────────────────────────
            if !appState.lastTranscription.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Last text")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)

                        Spacer()

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(appState.lastTranscription, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .imageScale(.small)
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Copy")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                    Text(appState.lastTranscription)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                        .textSelection(.enabled)
                }
            }

            // ── Quota Banner (prominent) ─────────────────────────
            if appState.isQuotaExceeded {
                Divider()
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "creditcard.trianglebadge.exclamationmark")
                            .foregroundStyle(.orange)
                        Text("OpenAI credit used up")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    Text("Top up your credit so SPEXT works again.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Top up credit now →") {
                        if let url = URL(string: "https://platform.openai.com/settings/organization/billing") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.08))
            }

            // ── Other Error Message ──────────────────────────────
            if let err = appState.errorMessage, !appState.isQuotaExceeded {
                Divider()

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .imageScale(.small)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 8) {
                        ScrollView {
                            Text(err)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 64)

                        VStack(alignment: .leading, spacing: 6) {
                            if !appState.hasInputMonitoringPermission {
                                Button("Open Input Monitoring") {
                                    appState.requestInputMonitoring()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            if !appState.hasAccessibilityPermission {
                                Button("Open Accessibility") {
                                    appState.requestAccessibility()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            Divider()

            // ── Hotkey Hint ──────────────────────────────────────
            VStack(spacing: 6) {
                HotkeyHintRow(
                    icon:    "waveform",
                    color:   .red,
                    label:   "Dictate",
                    keyName: HotkeyManager.label(for: appState.hotkeyFlags1)
                )
                HotkeyHintRow(
                    icon:    "sparkles",
                    color:   .blue,
                    label:   "Message",
                    keyName: HotkeyManager.label(for: appState.hotkeyFlags2)
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // ── Footer Buttons ───────────────────────────────────
            HStack {
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 320)
        .background(.regularMaterial)
        .onAppear { appState.checkPermissions() }
    }

}

// MARK: - Hotkey Hint Row

private struct HotkeyHintRow: View {
    let icon:    String
    let color:   Color
    let label:   LocalizedStringKey
    let keyName: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .imageScale(.small)
                .foregroundStyle(color)
                .frame(width: 14)

            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Text(keyName)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.vertical, 2)
                .padding(.horizontal, 6)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}
