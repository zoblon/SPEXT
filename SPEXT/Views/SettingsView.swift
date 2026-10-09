import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab        = 0
    @State private var isCapturingHotkey  = false
    @State private var isCapturingHotkey2 = false
    @State private var showAPIKey         = false

    /// App version from the bundle – kept up to date automatically
    private var appVersionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "SPEXT \(v)"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                TabButton(title: "General",    index: 0, selected: $selectedTab)
                TabButton(title: "Access",     index: 1, selected: $selectedTab)
                TabButton(title: "Dictionary", index: 2, selected: $selectedTab)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider()
                .onAppear { appState.checkPermissions() }

            Group {
                if selectedTab == 0 {
                    GeneralTab(
                        isCapturingHotkey:  $isCapturingHotkey,
                        isCapturingHotkey2: $isCapturingHotkey2
                    )
                } else if selectedTab == 1 {
                    AccessTab(showAPIKey: $showAPIKey)
                } else {
                    DictionaryTab()
                }
            }
            .environmentObject(appState)

            Divider()

            // Version display – read automatically from the app bundle
            Text(appVersionString)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
        }
        .frame(width: 460, height: 490)
        .background(.regularMaterial)
    }
}

// MARK: - Tab Button

private struct TabButton: View {
    let title: LocalizedStringKey
    let index: Int
    @Binding var selected: Int

    var body: some View {
        Button(title) { selected = index }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: selected == index ? .semibold : .regular))
            .foregroundStyle(selected == index ? .primary : .secondary)
            .padding(.vertical, 6)
            .padding(.horizontal, 14)
            .background(
                Capsule()
                    .fill(selected == index ? Color.accentColor.opacity(0.15) : Color.clear)
            )
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    @EnvironmentObject var appState: AppState
    @Binding var isCapturingHotkey:  Bool
    @Binding var isCapturingHotkey2: Bool
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {

                // MODES
                SettingsSection(title: "MODES") {
                    ModeRow(
                        icon:    "waveform",
                        color:   .red,
                        title:   "Direct transcription",
                        detail:  "Speech is transcribed 1:1 and inserted immediately.",
                        flags:   appState.hotkeyFlags1,
                        isCapturing: $isCapturingHotkey
                    ) { isCapturingHotkey.toggle() }

                    ModeRow(
                        icon:    "sparkles",
                        color:   .blue,
                        title:   "Write message",
                        detail:  "The recording is transcribed and then written as a polite message.",
                        flags:   appState.hotkeyFlags2,
                        isCapturing: $isCapturingHotkey2
                    ) { isCapturingHotkey2.toggle() }
                }

                // Language + processing
                SettingsSection(title: "PROCESSING") {
                    LabelPickerRow("Language") {
                        Picker("", selection: $appState.language) {
                            Text("German").tag("de")
                            Text("English").tag("en")
                            Text("Automatic").tag("")
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    LabelPickerRow("Transcription") {
                        Text(verbatim: "GPT Transcribe")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    LabelPickerRow("Rewriting") {
                        Text(verbatim: "GPT-6.1 Sol")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Text("Rewriting is only used for mode 2 (Write message).")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                // Microphone
                SettingsSection(title: "MICROPHONE") {
                    ToggleRow(
                        title: "Use AirPods automatically",
                        detail: "Turn off to dictate with a different microphone.",
                        isOn: $appState.preferAirPods
                    )
                    LabelPickerRow(appState.preferAirPods ? "Fallback" : "Microphone") {
                        Picker("", selection: $appState.selectedMicUID) {
                            Text("Default microphone").tag("")
                            ForEach(appState.availableDevices) { device in
                                Text(device.name).tag(device.id)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .onAppear { appState.refreshDevices() }
                    }

                    // Active microphone – updates live when the device changes
                    HStack(spacing: 6) {
                        Image(systemName: (appState.preferAirPods && appState.allDevicesCache.contains(where: { $0.isAirPods }))
                              ? "airpodspro" : "mic")
                            .imageScale(.small)
                            .foregroundStyle((appState.preferAirPods && appState.allDevicesCache.contains(where: { $0.isAirPods }))
                                             ? Color.accentColor : .secondary)
                        Text("Active: \(appState.effectiveMicName)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    Text("With the automatic selection turned off, your microphone choice also applies when AirPods are connected. This lets you listen through the AirPods and dictate through the Mac's microphone.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                // System
                SettingsSection(title: "SYSTEM") {
                    ToggleRow(
                        title:  "Launch at login",
                        detail: "SPEXT starts automatically after every restart.",
                        isOn:   $launchAtLogin
                    )
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else       { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }

                    ToggleRow(
                        title:  "Mute system sound",
                        detail: "Music and sounds are paused while recording.",
                        isOn:   $appState.muteOnRecord
                    )
                }
            }
            .padding(20)
        }
        // Modifier combination capture for hotkey 1 and 2
        .background(FlagCaptureView(isCapturing: $isCapturingHotkey) { flags in
            appState.hotkeyFlagsRaw1 = Int(flags.rawValue)
            appState.setupHotkeys()
            isCapturingHotkey = false
        })
        .background(FlagCaptureView(isCapturing: $isCapturingHotkey2) { flags in
            appState.hotkeyFlagsRaw2 = Int(flags.rawValue)
            appState.setupHotkeys()
            isCapturingHotkey2 = false
        })
    }
}

// MARK: - Mode Row

private struct ModeRow: View {
    let icon:       String
    let color:      Color
    let title:      LocalizedStringKey
    let detail:     LocalizedStringKey
    let flags:      CGEventFlags
    @Binding var isCapturing: Bool
    let onChangeTap: () -> Void

    /// The hotkey is a technical label (e.g. "ROPT+RCMD") and is not localized.
    private var hotkeyLabel: Text {
        isCapturing ? Text("Hold & release…") : Text(verbatim: HotkeyManager.label(for: flags))
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7)
                .fill(color.opacity(0.15))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: icon)
                        .foregroundStyle(color)
                        .imageScale(.medium)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            hotkeyLabel
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(isCapturing ? .secondary : .primary)
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isCapturing ? color : Color(.separatorColor), lineWidth: 1)
                )

            Button(isCapturing ? "✕" : "Change") { onChangeTap() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(12)
        .background(Color(.controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.separatorColor).opacity(0.5), lineWidth: 0.5)
        )
    }
}

// MARK: - Label Picker Row

private struct LabelPickerRow<P: View>: View {
    let label: LocalizedStringKey
    @ViewBuilder let picker: () -> P

    init(_ label: LocalizedStringKey, @ViewBuilder picker: @escaping () -> P) {
        self.label  = label
        self.picker = picker
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            picker()
        }
        .padding(12)
        .background(Color(.controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.separatorColor).opacity(0.5), lineWidth: 0.5)
        )
    }
}

// MARK: - Toggle Row

private struct ToggleRow: View {
    let title:  LocalizedStringKey
    let detail: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch)
        }
        .padding(12)
        .background(Color(.controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.separatorColor).opacity(0.5), lineWidth: 0.5)
        )
    }
}

// MARK: - Access Tab

private struct AccessTab: View {
    @EnvironmentObject var appState: AppState
    @Binding var showAPIKey: Bool

    /// Shows the step-by-step guide for Accessibility
    @State private var showAccessibilitySteps = false
    /// Shows the step-by-step guide for Input Monitoring
    @State private var showInputMonitoringSteps = false
    /// Timer that checks the permission status automatically while the guide is visible
    @State private var pollTimer: Timer?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {

                // API Key
                SettingsSection(title: "OPENAI API KEY") {
                    HStack(spacing: 6) {
                        // Binding that automatically strips spaces and line breaks
                        let sanitized = Binding(
                            get: { appState.apiKey },
                            set: { appState.apiKey = $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        )

                        Group {
                            if showAPIKey {
                                TextField("sk-…", text: sanitized)
                            } else {
                                SecureField("sk-…", text: sanitized)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))

                        // Delete
                        if !appState.apiKey.isEmpty {
                            Button {
                                appState.apiKey = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .help("Delete API key")
                        }

                        // Visibility
                        Button {
                            showAPIKey.toggle()
                        } label: {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Create an API key at platform.openai.com → API keys. Cost: about $0.0045 per minute of recording.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                // Permissions
                SettingsSection(title: "PERMISSIONS") {
                    // Input Monitoring
                    PermissionRow(
                        icon:    "keyboard",
                        title:   "Input Monitoring",
                        detail:  "Required so global hotkeys also work outside SPEXT.",
                        granted: appState.hasInputMonitoringPermission
                    ) {
                        appState.requestInputMonitoring()
                        showInputMonitoringSteps = true
                        startPolling()
                    }

                    // Inline guide while the permission is missing and the button was pressed
                    if showInputMonitoringSteps && !appState.hasInputMonitoringPermission {
                        InputMonitoringInstructionsView {
                            appState.requestInputMonitoring()
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Accessibility
                    PermissionRow(
                        icon:    "hand.raised",
                        title:   "Accessibility",
                        detail:  "Required for automatic pasting via ⌘V. Input Monitoring is not enough for that.",
                        granted: appState.hasAccessibilityPermission
                    ) {
                        appState.requestAccessibility()
                        showAccessibilitySteps = true
                        startPolling()
                    }

                    // Inline guide while the permission is missing and the button was pressed
                    if showAccessibilitySteps && !appState.hasAccessibilityPermission {
                        AccessibilityInstructionsView {
                            // "Open again" button
                            appState.requestAccessibility()
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    PermissionRow(
                        icon:    "mic",
                        title:   "Microphone",
                        detail:  "Required for voice recording.",
                        granted: appState.hasMicrophonePermission
                    ) {
                        appState.requestMicrophone()
                    }
                }
            }
            .padding(20)
            .animation(.easeInOut(duration: 0.2), value: showAccessibilitySteps)
            .animation(.easeInOut(duration: 0.2), value: showInputMonitoringSteps)
            .animation(.easeInOut(duration: 0.2), value: appState.hasAccessibilityPermission)
            .animation(.easeInOut(duration: 0.2), value: appState.hasInputMonitoringPermission)
        }
        .onChange(of: appState.hasAccessibilityPermission) { _, granted in
            if granted {
                showAccessibilitySteps = false
                if !showInputMonitoringSteps { stopPolling() }
            }
        }
        .onChange(of: appState.hasInputMonitoringPermission) { _, granted in
            if granted {
                appState.setupHotkeys()
                showInputMonitoringSteps = false
                if !showAccessibilitySteps { stopPolling() }
            }
        }
        .onDisappear { stopPolling() }
    }

    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            appState.checkPermissions()
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}

// MARK: - Input Monitoring Guide

private struct InputMonitoringInstructionsView: View {
    let onReopen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("System Settings was opened", systemImage: "arrow.up.right.square")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 6) {
                StepRow(number: "1", text: "Go to **Privacy & Security → Input Monitoring**")
                StepRow(number: "2", text: "Click **+** and add **SPEXT** from your Applications folder")
                StepRow(number: "3", text: "Turn on the switch next to **SPEXT**")
                StepRow(number: "4", text: "**Accessibility** is a different section and does not replace this permission")
                StepRow(number: "5", text: "Restart SPEXT if macOS asks you to")
            }

            HStack {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
                Text("Checking automatically…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Reopen System Settings") { onReopen() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

// MARK: - Accessibility Guide

private struct AccessibilityInstructionsView: View {
    let onReopen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("System Settings was opened", systemImage: "arrow.up.right.square")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 6) {
                StepRow(number: "1", text: "Go to **Privacy & Security → Accessibility**")
                StepRow(number: "2", text: "Click **+** and add **SPEXT** from your Applications folder")
                StepRow(number: "3", text: "Turn on the switch next to **SPEXT**")
                StepRow(number: "4", text: "**Input Monitoring** is a different section and is not enough for automatic pasting")
                StepRow(number: "5", text: "Return to SPEXT – the status updates automatically")
            }

            HStack {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
                Text("Checking automatically…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Reopen System Settings") { onReopen() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

private struct StepRow: View {
    let number: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.accentColor))

            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Helper Structures

private struct SettingsSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
                .kerning(0.8)

            VStack(alignment: .leading, spacing: 8) {
                content
            }
        }
    }
}

private struct PermissionRow: View {
    let icon:    String
    let title:   LocalizedStringKey
    let detail:  LocalizedStringKey
    let granted: Bool
    let action:  () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7)
                .fill(granted ? Color.green.opacity(0.12) : Color(.controlBackgroundColor))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: icon)
                        .foregroundStyle(granted ? .green : .secondary)
                        .imageScale(.medium)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            } else {
                Button("Allow") { action() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.accentColor)
            }
        }
        .padding(12)
        .background(granted ? Color.green.opacity(0.05) : Color(.controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    granted ? Color.green.opacity(0.25) : Color(.separatorColor).opacity(0.5),
                    lineWidth: 0.5
                )
        )
        .animation(.easeInOut(duration: 0.2), value: granted)
    }
}

// MARK: - Dictionary Tab

private struct DictionaryTab: View {
    @EnvironmentObject var appState: AppState
    @State private var newWord      = ""
    @State private var editingWord:  String? = nil   // Original word currently being edited
    @State private var editingText   = ""
    @FocusState private var fieldFocused:  Bool
    @FocusState private var editFocused:   Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SettingsSection(title: "CUSTOM WORDS") {
                        Text("GPT Transcribe uses this list as keyword hints. Ideal for proper names, technical terms or words that are often misrecognized.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        // Word list
                        if appState.customWords.isEmpty {
                            Text("No words added yet.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 12)
                        } else {
                            VStack(spacing: 4) {
                                ForEach(appState.customWords, id: \.self) { word in
                                    if editingWord == word {
                                        // ── Edit mode ──────────────────────────
                                        HStack(spacing: 6) {
                                            TextField("", text: $editingText)
                                                .textFieldStyle(.roundedBorder)
                                                .font(.system(size: 12))
                                                .focused($editFocused)
                                                .onSubmit { commitEdit(original: word) }

                                            Button { commitEdit(original: word) } label: {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(.green)
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(editingText.trimmingCharacters(in: .whitespaces).isEmpty)

                                            Button { editingWord = nil } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundStyle(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.accentColor.opacity(0.07))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                                        )
                                        .onAppear { editFocused = true }
                                    } else {
                                        // ── Display mode ──────────────────────
                                        HStack {
                                            Text(word)
                                                .font(.system(size: 12, weight: .medium))
                                            Spacer()

                                            Button {
                                                editingWord = word
                                                editingText = word
                                            } label: {
                                                Image(systemName: "pencil")
                                                    .foregroundStyle(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                            .help("Edit")

                                            Button {
                                                appState.customWords.removeAll { $0 == word }
                                            } label: {
                                                Image(systemName: "minus.circle.fill")
                                                    .foregroundStyle(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                            .help("Remove")
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(Color(.controlBackgroundColor).opacity(0.6))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color(.separatorColor).opacity(0.5), lineWidth: 0.5)
                                        )
                                    }
                                }
                            }
                        }

                        // Add new word
                        HStack(spacing: 8) {
                            TextField("New word or name…", text: $newWord)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                                .focused($fieldFocused)
                                .onSubmit { addWord() }

                            Button("Add") { addWord() }
                                .buttonStyle(.bordered)
                                .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    private func addWord() {
        let updated = CustomWordList.adding(newWord, to: appState.customWords)
        guard updated != appState.customWords else { return }
        appState.customWords = updated
        newWord = ""
        fieldFocused = true
    }

    private func commitEdit(original: String) {
        let w = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty else { editingWord = nil; return }
        appState.customWords = CustomWordList.replacing(
            original: original,
            with: w,
            in: appState.customWords
        )
        editingWord = nil
    }
}

// MARK: - Modifier Combination Capture

/// Captures the next modifier combination the user presses and releases.
struct FlagCaptureView: NSViewRepresentable {
    @Binding var isCapturing: Bool
    let onCapture: (CGEventFlags) -> Void

    func makeNSView(context: Context) -> FlagCaptureNSView {
        let v = FlagCaptureNSView()
        v.onCapture = onCapture
        return v
    }
    func updateNSView(_ nsView: FlagCaptureNSView, context: Context) {
        nsView.isCapturing = isCapturing
    }
}

class FlagCaptureNSView: NSView {
    var onCapture: ((CGEventFlags) -> Void)?
    var isCapturing = false {
        didSet { isCapturing ? startMonitor() : stopMonitor() }
    }

    private var monitor:   Any?
    private var peakFlags: CGEventFlags = []

    private func startMonitor() {
        peakFlags = []
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.process(event)
            return event
        }
    }

    private func stopMonitor() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        peakFlags = []
    }

    private func process(_ event: NSEvent) {
        guard isCapturing else { return }

        // CGEvent.flags contains device-specific L/R bits; NSEvent.modifierFlags does not.
        // Read directly from CGEvent so ROPT+RCMD can be distinguished from LOPT+LCMD.
        let current: CGEventFlags
        if let cgFlags = event.cgEvent?.flags {
            current = cgFlags.intersection(HotkeyManager.knownModifiers)
        } else {
            // Fall back to generic bits if no CGEvent is available
            var fallback: CGEventFlags = []
            let mf = event.modifierFlags
            if mf.contains(.control) { fallback.insert(.maskControl) }
            if mf.contains(.option)  { fallback.insert(.maskAlternate) }
            if mf.contains(.shift)   { fallback.insert(.maskShift) }
            if mf.contains(.command) { fallback.insert(.maskCommand) }
            current = fallback
        }

        peakFlags.formUnion(current)

        // Once all keys are released: report the combination
        if current.isEmpty, !peakFlags.isEmpty {
            let captured = peakFlags
            peakFlags = []
            onCapture?(captured)
        }
    }

    override var acceptsFirstResponder: Bool { true }
}
