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
                TabButton(title: "Allgemein",   index: 0, selected: $selectedTab)
                TabButton(title: "Zugang",      index: 1, selected: $selectedTab)
                TabButton(title: "Wörterbuch",  index: 2, selected: $selectedTab)
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
    let title: String
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
                SettingsSection(title: "MODI") {
                    ModeRow(
                        icon:    "waveform",
                        color:   .red,
                        title:   "Direkte Transkription",
                        detail:  "Sprache wird 1:1 transkribiert und sofort eingefügt.",
                        flags:   appState.hotkeyFlags1,
                        isCapturing: $isCapturingHotkey
                    ) { isCapturingHotkey.toggle() }

                    ModeRow(
                        icon:    "sparkles",
                        color:   .blue,
                        title:   "Nachricht schreiben",
                        detail:  "Die Aufnahme wird transkribiert und anschließend als höfliche Nachricht formuliert.",
                        flags:   appState.hotkeyFlags2,
                        isCapturing: $isCapturingHotkey2
                    ) { isCapturingHotkey2.toggle() }
                }

                // Language + processing
                SettingsSection(title: "VERARBEITUNG") {
                    LabelPickerRow("Sprache") {
                        Picker("", selection: $appState.language) {
                            Text("Deutsch").tag("de")
                            Text("Englisch").tag("en")
                            Text("Automatisch").tag("")
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    LabelPickerRow("Transkription") {
                        Text("GPT Transcribe")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    LabelPickerRow("Umformulierung") {
                        Text("GPT-6.1 Sol")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Text("Umformulierung wird nur für Modus 2 (Nachricht schreiben) verwendet.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                // Microphone
                SettingsSection(title: "MIKROFON") {
                    ToggleRow(
                        title: "AirPods automatisch verwenden",
                        detail: "Zum Diktieren über ein anderes Mikrofon ausschalten.",
                        isOn: $appState.preferAirPods
                    )
                    LabelPickerRow(appState.preferAirPods ? "Fallback" : "Mikrofon") {
                        Picker("", selection: $appState.selectedMicUID) {
                            Text("Standard-Mikrofon").tag("")
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
                        Text("Aktiv: \(appState.effectiveMicName)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    Text("Bei ausgeschalteter Automatik gilt deine Mikrofonwahl auch mit verbundenen AirPods. So kannst du über die AirPods hören und über das Mac-Mikrofon diktieren.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                // System
                SettingsSection(title: "SYSTEM") {
                    ToggleRow(
                        title:  "Bei Anmeldung starten",
                        detail: "SPEXT startet automatisch nach jedem Neustart.",
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
                        title:  "Systemton stummschalten",
                        detail: "Musik und Töne werden während der Aufnahme pausiert.",
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
    let title:      String
    let detail:     String
    let flags:      CGEventFlags
    @Binding var isCapturing: Bool
    let onChangeTap: () -> Void

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

            Text(isCapturing ? "Halten & loslassen…" : HotkeyManager.label(for: flags))
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

            Button(isCapturing ? "✕" : "Ändern") { onChangeTap() }
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
    let label: String
    @ViewBuilder let picker: () -> P

    init(_ label: String, @ViewBuilder picker: @escaping () -> P) {
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
    let title:  String
    let detail: String
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
                            .help("API Key löschen")
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

                    Text("Erstelle einen API Key unter platform.openai.com → API keys. Kosten: ca. $0,0045 pro Minute Aufnahme.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                // Permissions
                SettingsSection(title: "BERECHTIGUNGEN") {
                    // Input Monitoring
                    PermissionRow(
                        icon:    "keyboard",
                        title:   "Eingabeüberwachung",
                        detail:  "Notwendig, damit globale Hotkeys auch außerhalb von SPEXT reagieren.",
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
                        title:   "Bedienungshilfen",
                        detail:  "Notwendig für automatisches Einfügen per ⌘V. Eingabeüberwachung reicht dafür nicht.",
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
                        title:   "Mikrofon",
                        detail:  "Notwendig für die Sprachaufnahme.",
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
            Label("Systemeinstellungen wurden geöffnet", systemImage: "arrow.up.right.square")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 6) {
                StepRow(number: "1", text: "Gehe zu **Datenschutz & Sicherheit → Eingabeüberwachung**")
                StepRow(number: "2", text: "Klicke auf **+** und füge **SPEXT** aus deinem Programme-Ordner hinzu")
                StepRow(number: "3", text: "Aktiviere den Schalter neben **SPEXT**")
                StepRow(number: "4", text: "**Bedienungshilfen** ist ein anderer Bereich und ersetzt diese Freigabe nicht")
                StepRow(number: "5", text: "Starte SPEXT neu, falls macOS dich dazu auffordert")
            }

            HStack {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
                Text("Prüfe automatisch…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Systemeinstellungen erneut öffnen") { onReopen() }
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
            Label("Systemeinstellungen wurden geöffnet", systemImage: "arrow.up.right.square")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 6) {
                StepRow(number: "1", text: "Gehe zu **Datenschutz & Sicherheit → Bedienungshilfen**")
                StepRow(number: "2", text: "Klicke auf **+** und füge **SPEXT** aus deinem Programme-Ordner hinzu")
                StepRow(number: "3", text: "Aktiviere den Schalter neben **SPEXT**")
                StepRow(number: "4", text: "**Eingabeüberwachung** ist ein anderer Bereich und reicht für das automatische Einfügen nicht aus")
                StepRow(number: "5", text: "Kehre zu SPEXT zurück – der Status aktualisiert sich automatisch")
            }

            HStack {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
                Text("Prüfe automatisch…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Systemeinstellungen erneut öffnen") { onReopen() }
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
    let title: String
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
    let title:   String
    let detail:  String
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
                Label("Erteilt", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            } else {
                Button("Erlauben") { action() }
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
                    SettingsSection(title: "EIGENE WÖRTER") {
                        Text("GPT Transcribe nutzt diese Liste als Keyword-Hinweise. Ideal für Eigennamen, Fachbegriffe oder Wörter, die oft falsch erkannt werden.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        // Word list
                        if appState.customWords.isEmpty {
                            Text("Noch keine Wörter eingetragen.")
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
                                            .help("Bearbeiten")

                                            Button {
                                                appState.customWords.removeAll { $0 == word }
                                            } label: {
                                                Image(systemName: "minus.circle.fill")
                                                    .foregroundStyle(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                            .help("Entfernen")
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
                            TextField("Neues Wort oder Name…", text: $newWord)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                                .focused($fieldFocused)
                                .onSubmit { addWord() }

                            Button("Hinzufügen") { addWord() }
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
