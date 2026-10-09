import AppKit
import AVFoundation
import Combine
import CoreAudio
import CoreGraphics
import Foundation
import OSLog
import SwiftUI

private let appStateLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "de.Rehkopf.SPEXT",
    category: "AppState"
)

// MARK: - AppState

class AppState: ObservableObject {

    // MARK: - Published State

    @Published var isRecording     = false
    @Published var isTranscribing  = false
    /// Prevents a race condition when the hotkey fires twice during async engine init.
    private    var isStarting      = false
    @Published var isMicReady      = false
    @Published var signalWarning   = false
    private var recordingWarning: String?
    @Published var currentMode:    RecordingMode = .direct
    @Published var isQuotaExceeded = false
    @Published var lastTranscription = ""
    @Published var statusMessage   = "Bereit"
    @Published var errorMessage:   String?
    @Published var audioLevel:     Float  = 0
    @Published var availableDevices: [AudioDevice] = []
    /// Cache of all audio devices (input + output) – updated in refreshDevices().
    /// Avoids repeated CoreAudio syscalls in effectiveMicUID / effectiveMicName.
    private(set) var allDevicesCache: [AudioDevice] = []

    /// Custom words for GPT-Transcribe keywords (proper names, technical terms …)
    @Published var customWords: [String] = {
        guard let data  = UserDefaults.standard.data(forKey: "tt_customWords"),
              let words = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return words
    }() {
        didSet {
            if let data = try? JSONEncoder().encode(customWords) {
                UserDefaults.standard.set(data, forKey: "tt_customWords")
            }
        }
    }

    @Published var hasAccessibilityPermission = false
    @Published var hasInputMonitoringPermission = false
    @Published var hasMicrophonePermission    = false

    // MARK: - Persisted Settings

    /// The API key lives in the Keychain (not in UserDefaults).
    /// @Published so SwiftUI views re-render when it is set.
    /// The value is loaded from the Keychain on init and, on every change,
    /// trimmed and written back.
    @Published var apiKey: String = "" {
        didSet {
            guard !isRollingBackAPIKey else { return }
            let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                guard KeychainService.deleteAPIKey() else {
                    reportKeychainFailure(previousValue: oldValue)
                    return
                }
            } else if !KeychainService.saveAPIKey(trimmed) {
                reportKeychainFailure(previousValue: oldValue)
            }
        }
    }
    private var isRollingBackAPIKey = false

    @AppStorage("tt_preferAirPods")     var preferAirPods        = true
    @AppStorage("tt_microphoneUID")     var selectedMicUID      = ""
    @AppStorage("tt_microphoneName")    var selectedMicName     = "Standard-Mikrofon"
    @AppStorage("tt_language")          var language            = "de"
    @AppStorage("tt_muteOnRecord")      var muteOnRecord        = false

    // Hotkey flags stored as Int (CGEventFlags.rawValue, fits into Int on 64-bit)
    // Default: mode 1 = ROPT+RCMD, mode 2 = RCTRL+ROPT.
    @AppStorage("tt_hotkeyFlags1_v4")   var hotkeyFlagsRaw1: Int = HotkeySettings.defaultDirectRaw
    @AppStorage("tt_hotkeyFlags2_v4")   var hotkeyFlagsRaw2: Int = HotkeySettings.defaultPolishRaw

    var hotkeyFlags1: CGEventFlags { CGEventFlags(rawValue: UInt64(hotkeyFlagsRaw1)) }
    var hotkeyFlags2: CGEventFlags { CGEventFlags(rawValue: UInt64(hotkeyFlagsRaw2)) }

    // MARK: - Services (internal)

    let     audioRecorder  = AudioRecorder()
    private let transcription = TranscriptionService()
    private let polishSvc  = PolishService()
    private let paste      = PasteService()

    private(set) var hotkeyManager1:  HotkeyManager?
    private(set) var hotkeyManager2:  HotkeyManager?
    /// Created once, afterwards only show()/hide() are called – no allocation overhead per recording.
    private lazy var hudController = HUDWindowController(appState: self)
    private lazy var permissionSetupController = PermissionSetupWindowController(appState: self)
    private var levelCancellable:       AnyCancellable?
    private var micReadyCancellable:    AnyCancellable?
    private var signalCancellable:      AnyCancellable?
    private var deviceListenerBlock:    AudioObjectPropertyListenerBlock?
    private var defaultInputListenerBlock: AudioObjectPropertyListenerBlock?

    /// Called once as soon as the next CoreAudio device-change event fires.
    /// Used for the delayed unmute after the AirPods profile switch (HFP→A2DP).
    private var unmuteOnDeviceChange:   (() -> Void)?
    private var unmuteTimeoutWork:      DispatchWorkItem?
    private var recordingLimitWorkItem: DispatchWorkItem?

    private var audioRestoreSnapshot: SystemAudioController.RestoreSnapshot?
    private var activeRecorderSessionID: UUID?
    private var recordingOwner: RecordingMode?
    private var pasteTarget: PasteService.Target?
    private var deviceScanGeneration: UInt64 = 0

    // MARK: - Computed

    var menuBarIcon: String { "bolt.fill" }

    var menuBarColor: Color {
        if isRecording    { return currentMode == .polish ? .blue : .red }
        if isTranscribing { return .orange }
        return .primary
    }

    var statusColor: Color {
        if isRecording    { return currentMode == .polish ? .blue : .red }
        if isTranscribing { return .orange }
        if errorMessage != nil { return .red }
        return .green
    }

    var permissionChecklist: PermissionChecklist {
        PermissionChecklist(
            hasInputMonitoring: hasInputMonitoringPermission,
            hasAccessibility: hasAccessibilityPermission,
            hasMicrophone: hasMicrophonePermission
        )
    }

    /// UID of the microphone that is actually used.
    /// Uses the device cache from the CoreAudio listener so the hotkey path
    /// does not have to run synchronous CoreAudio scans.
    var effectiveMicUID: String? {
        AudioDevice.preferredMicrophoneUID(
            from: allDevicesCache,
            selectedMicUID: selectedMicUID,
            preferAirPods: preferAirPods
        )
    }

    /// Display name of the active microphone (for the settings view).
    /// Uses the cache, since freshness is less critical here.
    var effectiveMicName: String {
        if preferAirPods, let airpods = allDevicesCache.first(where: { $0.isAirPods }) {
            return "\(airpods.name) (automatisch)"
        }
        if !selectedMicUID.isEmpty,
           let device = availableDevices.first(where: { $0.id == selectedMicUID }) {
            return device.name
        }
        return "Standard-Mikrofon"
    }

    private var effectiveMicDevice: AudioDevice? {
        cachedDevice(forUID: effectiveMicUID)
    }

    private func cachedDevice(forUID uid: String?) -> AudioDevice? {
        guard let uid else { return nil }
        return allDevicesCache.first { $0.id == uid }
            ?? availableDevices.first { $0.id == uid }
    }

    // MARK: - Init

    init() {
        migrateAPIKeyToKeychain()
        TranscriptionConfiguration.removeLegacyModelPreference(from: .standard)
        PolishConfiguration.removeLegacyModelPreference(from: .standard)
        // Load the Keychain value WITHOUT triggering didSet (it would save again otherwise)
        _apiKey = Published(initialValue: KeychainService.loadAPIKey())
        migrateHotkeyDefaults()
        refreshDevices()
        checkPermissions()
        setupHotkeys()
        setupDeviceMonitor()
        levelCancellable = audioRecorder.$audioLevel
            .receive(on: DispatchQueue.main)
            .assign(to: \.audioLevel, on: self)
        micReadyCancellable = audioRecorder.$isMicReady
            .receive(on: DispatchQueue.main)
            .assign(to: \.isMicReady, on: self)

        signalCancellable = audioRecorder.$signalWarning
            .receive(on: DispatchQueue.main)
            .assign(to: \.signalWarning, on: self)

        // Prepare the NSPanel + SwiftUI view invisibly after app launch.
        // On the first hotkey the HUD then only needs to be shown.
        DispatchQueue.main.async { [weak self] in
            self?.hudController.prepare()
            appStateLogger.info("HUD prepared")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.presentPermissionSetupIfNeeded()
        }

        // Callback for internally aborted recordings (e.g. a failed HFP restart)
        audioRecorder.onRecordingFailed = { [weak self] message in
            guard let self else { return }
            self.isStarting = false
            self.isTranscribing = false
            self.recordingOwner = nil
            self.cancelRecordingLimit()
            self.errorMessage  = message
            self.statusMessage = "Mikrofon-Fehler"
            self.isRecording   = false
            self.hudController.hide()
            self.scheduleSystemAudioRestore(afterAirPods: self.audioRecorder.recordingDeviceIsAirPods)
        }
#if SPEXT_AUDIO_DIAGNOSTICS
        if ProcessInfo.processInfo.arguments.contains("--spext-mic-diagnostic") {
            isStarting = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
                let uid = effectiveMicUID
                appStateLogger.info("Local diagnostic begin; no API upload")
                _ = audioRecorder.startRecording(deviceUID: uid, knownDevice: cachedDevice(forUID: uid)) { result in
                    appStateLogger.info("Local diagnostic start succeeded=\(result.succeeded, privacy: .public)")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [self] in
                    audioRecorder.stopRecording { result in
                        if let url = result.url { try? FileManager.default.removeItem(at: url) }
                        appStateLogger.info("Local diagnostic end frames=\(result.statistics?.writtenFrames ?? 0, privacy: .public) duration=\(result.statistics?.audioDuration ?? 0, privacy: .public)")
                        DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
                    }
                }
            }
        }
#endif
    }

    // MARK: - Migration

    /// One-time migration: move an existing API key from UserDefaults into the Keychain.
    private func migrateAPIKeyToKeychain() {
        let legacyKey = "tt_apiKey"
        guard let oldKey = UserDefaults.standard.string(forKey: legacyKey),
              !oldKey.isEmpty else { return }
        let existing = KeychainService.loadAPIKey()
        let saveSucceeded = existing.isEmpty ? KeychainService.saveAPIKey(oldKey) : false
        let readback = KeychainService.loadAPIKey()
        if KeychainMigrationPolicy.shouldRemoveLegacy(
            existingKey: existing,
            attemptedKey: oldKey,
            saveSucceeded: saveSucceeded,
            readbackKey: readback
        ) {
            UserDefaults.standard.removeObject(forKey: legacyKey)
        } else {
            errorMessage = "Der API-Key konnte nicht sicher im Schlüsselbund gespeichert werden. Der bisherige Wert bleibt erhalten."
        }
    }

    private func reportKeychainFailure(previousValue: String) {
        isRollingBackAPIKey = true
        apiKey = previousValue
        isRollingBackAPIKey = false
        errorMessage = "Der API-Key konnte nicht im Schlüsselbund gespeichert werden. Der bisherige Wert bleibt erhalten."
        statusMessage = "Schlüsselbund-Fehler"
    }

    /// Migrates the briefly used side-independent defaults back
    /// to right-side-specific hotkeys. Other manually captured combinations are kept.
    private func migrateHotkeyDefaults() {
        let normalized1 = HotkeySettings.normalizedStoredRaw(hotkeyFlagsRaw1)
        if normalized1 != hotkeyFlagsRaw1 {
            hotkeyFlagsRaw1 = normalized1
        }

        let normalized2 = HotkeySettings.normalizedStoredRaw(hotkeyFlagsRaw2)
        if normalized2 != hotkeyFlagsRaw2 {
            hotkeyFlagsRaw2 = normalized2
        }
    }

    // MARK: - Setup

    func refreshDevices() {
        deviceScanGeneration &+= 1
        let generation = deviceScanGeneration
        // CoreAudio syscalls on a background thread so the main thread is not blocked.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let allDevices   = AudioDevice.allAudioDevices()
            let inputDevices = allDevices.filter(\.hasInput)
            DispatchQueue.main.async { [self] in
                guard let self,
                      GenerationPolicy.shouldApply(completed: generation, latest: self.deviceScanGeneration)
                else { return }
                self.allDevicesCache  = allDevices
                self.availableDevices = inputDevices

                // If we are waiting for the A2DP profile switch after stopping an
                // AirPods recording: unmute shortly after the device-change event.
                // (The event fires when the HFP device disappears / the A2DP device appears.)
                if let action = self.unmuteOnDeviceChange {
                    self.unmuteTimeoutWork?.cancel()
                    // This delay also stays cancellable in case a new dictation starts right away.
                    let work = DispatchWorkItem { [weak self] in
                        guard let self, self.unmuteOnDeviceChange != nil else { return }
                        self.unmuteOnDeviceChange = nil
                        self.unmuteTimeoutWork = nil
                        action()
                    }
                    self.unmuteTimeoutWork = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
                }
            }
        }
    }

    private func setupDeviceMonitor() {
        // CoreAudio listener: fires reliably for Bluetooth devices too (AirPods)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.refreshDevices()
        }
        deviceListenerBlock = block  // Retain the block so it is not deallocated
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )

        var defaultInputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let defaultBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.refreshDevices()
        }
        defaultInputListenerBlock = defaultBlock
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputAddress,
            DispatchQueue.main,
            defaultBlock
        )
    }

    func checkPermissions() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as NSDictionary
        hasAccessibilityPermission = AXIsProcessTrustedWithOptions(opts)
        hasInputMonitoringPermission = InputMonitoringPermission.isGranted
        hasMicrophonePermission    = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        updatePermissionStatusMessages()
    }

    func setupHotkeys() {
        hotkeyManager1?.teardown()
        hotkeyManager2?.teardown()

        hotkeyManager1 = HotkeyManager(triggerFlags: hotkeyFlags1)
        hotkeyManager1?.onKeyDown = { [weak self] in
            self?.startRecording(mode: .direct)
        }
        hotkeyManager1?.onKeyUp = { [weak self] in
            self?.stopAndTranscribe(triggeredBy: .direct)
        }

        hotkeyManager2 = HotkeyManager(triggerFlags: hotkeyFlags2)
        hotkeyManager2?.onKeyDown = { [weak self] in
            self?.startRecording(mode: .polish)
        }
        hotkeyManager2?.onKeyUp = { [weak self] in
            self?.stopAndTranscribe(triggeredBy: .polish)
        }

        checkPermissions()
        if hotkeyManager1?.isInstalled != true || hotkeyManager2?.isInstalled != true {
            hasInputMonitoringPermission = InputMonitoringPermission.isGranted
            updatePermissionStatusMessages()
        }
    }

    // MARK: - Request Permissions

    func requestAccessibility() {
        HotkeyManager.requestAccessibilityPermission()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkPermissions()
        }
    }

    func requestPermission(_ permission: SPEXTPermission) {
        switch permission {
        case .inputMonitoring:
            requestInputMonitoring()
        case .accessibility:
            requestAccessibility()
        case .microphone:
            requestMicrophone()
        }
    }

    func requestMissingPermissions() {
        checkPermissions()
        let missing = permissionChecklist.missingPermissions

        if missing.contains(.inputMonitoring) {
            InputMonitoringPermission.request()
        }
        if missing.contains(.accessibility) {
            HotkeyManager.requestAccessibilityPermission()
        }
        if missing.contains(.microphone) {
            requestMicrophone()
        }

        if missing.contains(.inputMonitoring),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        } else if missing.contains(.accessibility),
                  let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkPermissions()
            self?.setupHotkeys()
        }
    }

    func presentPermissionSetupIfNeeded(force: Bool = false) {
        checkPermissions()
        guard force || permissionChecklist.needsSetup else {
            permissionSetupController.close()
            return
        }
        permissionSetupController.show()
    }

    func requestInputMonitoring() {
        InputMonitoringPermission.request()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkPermissions()
            self?.setupHotkeys()
        }
    }

    func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async { self?.hasMicrophonePermission = granted }
        }
    }

    private func updatePermissionStatusMessages() {
        guard !isRecording, !isTranscribing, !isStarting else { return }

        if !hasInputMonitoringPermission {
            statusMessage = AppStatusText.hotkeysBlocked
            errorMessage = AppStatusText.hotkeysBlockedExplanation
        } else if errorMessage == AppStatusText.hotkeysBlockedExplanation {
            errorMessage = nil
            statusMessage = "Bereit"
        }
    }

    private func scheduleRecordingLimit() {
        cancelRecordingLimit()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isRecording else { return }
            self.statusMessage = "Aufnahme-Limit erreicht"
            self.stopAndTranscribe(triggeredBy: nil)
        }
        recordingLimitWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + RecordingLimits.maximumDuration,
            execute: work
        )
    }

    private func cancelRecordingLimit() {
        recordingLimitWorkItem?.cancel()
        recordingLimitWorkItem = nil
    }

    // MARK: - Recording Lifecycle

    func startRecording(mode: RecordingMode = .direct) {
        guard !isRecording, !isTranscribing, !isStarting else { return }
        isStarting = true
        appStateLogger.info("Hotkey down mode=\(mode == .direct ? "direct" : "polish", privacy: .public)")

        guard !apiKey.isEmpty else {
            isStarting    = false
            errorMessage  = "Bitte OpenAI API Key in den Einstellungen eingeben."
            statusMessage = "Kein API Key"
            return
        }

        if !hasMicrophonePermission {
            isStarting = false
            requestMicrophone()
            return
        }

        // Finish the delayed unmute of the previous recording before muting again.
        unmuteTimeoutWork?.cancel()
        unmuteTimeoutWork = nil
        let pendingRestore = unmuteOnDeviceChange
        unmuteOnDeviceChange = nil
        pendingRestore?()
        recordingWarning = nil
        signalWarning = false
        currentMode   = mode
        recordingOwner = mode
        pasteTarget = paste.captureTarget()
        isRecording   = true
        statusMessage = mode == .direct ? "Aufnahme läuft…" : "Aufnahme (Nachricht)…"
        errorMessage  = nil
        hudController.show()
        scheduleRecordingLimit()
        appStateLogger.info("HUD shown")

        // Handle DNS/TLS/auth while the user is speaking so the actual
        // upload after releasing the keys can reuse an existing connection.
        transcription.prepareConnection(apiKey: apiKey)

        if muteOnRecord, audioRestoreSnapshot == nil {
            audioRestoreSnapshot = SystemAudioController.captureAndSilence()
        }
        appStateLogger.info("Mute handled enabled=\(self.muteOnRecord, privacy: .public)")

        let uid = effectiveMicUID
        let device = cachedDevice(forUID: uid)
        appStateLogger.info(
            "Device resolved uid=\(uid ?? "system-default", privacy: .public) name=\(device?.name ?? "System-Default", privacy: .public) bluetooth=\(device?.isBluetooth ?? false, privacy: .public) continuity=\(device?.isContinuityLike ?? false, privacy: .public)"
        )

        activeRecorderSessionID = audioRecorder.startRecording(deviceUID: uid, knownDevice: device) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                guard self.activeRecorderSessionID == result.sessionID else { return }
                self.isStarting = false
                if let err = result.errorMessage {
                    self.errorMessage  = err
                    self.statusMessage = "Aufnahme-Fehler"
                    self.isRecording   = false
                    self.cancelRecordingLimit()
                    self.hudController.hide()
                    self.scheduleSystemAudioRestore(afterAirPods: self.audioRecorder.recordingDeviceIsAirPods)
                }
            }
        }
    }

    func stopAndTranscribe(triggeredBy trigger: RecordingMode? = nil) {
        guard isRecording,
              RecordingOwnershipPolicy.mayStop(owner: recordingOwner, trigger: trigger) else { return }
        cancelRecordingLimit()
        isRecording = false
        isTranscribing = true
        statusMessage = "Aufnahme wird vorbereitet…"
        hudController.hide()
        let requestKey = apiKey
        let requestLanguage = language
        let requestWords = customWords
        let requestMode = currentMode

        let expectedSessionID = activeRecorderSessionID
        audioRecorder.stopRecording { [weak self] recordingResult in
            guard let self else { return }

            DispatchQueue.main.async { [self] in
                guard expectedSessionID == recordingResult.sessionID else { return }
                self.isRecording  = false
                self.audioLevel   = 0
                self.hudController.hide()

                if self.audioRestoreSnapshot != nil {
                    let airPodsActive = self.audioRecorder.recordingDeviceIsAirPods
                    self.scheduleSystemAudioRestore(afterAirPods: airPodsActive)
                }

                self.recordingWarning = recordingResult.warning
                guard let url = recordingResult.url else {
                    self.isTranscribing = false
                    if let err = recordingResult.errorMessage {
                        self.errorMessage  = err
                        self.statusMessage = "Aufnahme-Fehler"
                    } else {
                        self.statusMessage = "Bereit"
                    }
                    return
                }
                self.isTranscribing  = true
                self.statusMessage   = "Transkribiere…"

                self.transcription.transcribe(
                    audioURL:    url,
                    apiKey:      requestKey,
                    language:    requestLanguage,
                    customWords: requestWords
                ) { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success(let raw):
                        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                        if TranscriptionGuard.isDictionaryOnlyResult(t, customWords: requestWords) {
                            DispatchQueue.main.async {
                                self.isTranscribing = false
                                self.handleError(SPEXTError.dictionaryOnlyTranscription)
                            }
                            return
                        }

                        guard !t.isEmpty else {
                            DispatchQueue.main.async {
                                self.isTranscribing = false
                                self.statusMessage  = "Bereit"
                            }
                            return
                        }

                        if requestMode == .direct {
                            self.finishWithText(t)
                        } else {
                            DispatchQueue.main.async { self.statusMessage = "Wird umformuliert…" }
                            self.polishSvc.polish(
                                rawText: t,
                                apiKey:  requestKey
                            ) { [weak self] polishResult in
                                guard let self else { return }
                                switch polishResult {
                                case .success(let polished):
                                    self.finishWithText(polished)
                                case .failure(let err):
                                    DispatchQueue.main.async {
                                        self.isTranscribing = false
                                        self.lastTranscription = FrenchQuoteNormalizer.normalize(t)
                                        self.errorMessage = "Umformulierung fehlgeschlagen. Das ursprüngliche Diktat steht zum Kopieren bereit. \(err.localizedDescription)"
                                        self.statusMessage = "Diktat gesichert"
                                    }
                                }
                            }
                        }

                    case .failure(let err):
                        DispatchQueue.main.async {
                            self.isTranscribing = false
                            self.handleError(err)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Insert Text

    private func finishWithText(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isTranscribing    = false
            self.isQuotaExceeded   = false
            let normalizedText = FrenchQuoteNormalizer.normalize(text)
            self.lastTranscription = normalizedText   // store without trailing space (clean for copying)
            self.errorMessage      = nil

            if let warning = self.recordingWarning {
                self.errorMessage = warning
                self.statusMessage = "Text bitte prüfen"
                return
            }

            self.paste.paste(text: normalizedText + " ", target: self.pasteTarget) { [weak self] didPaste in
                guard let self else { return }
                if !didPaste {
                    self.errorMessage = AppStatusText.pasteTargetChangedExplanation
                    self.statusMessage = AppStatusText.pasteBlocked
                } else {
                    self.statusMessage = "Eingefügt"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if self.statusMessage == "Eingefügt" { self.statusMessage = "Bereit" }
                    }
                }
            }
        }
    }

    @discardableResult
    private func restoreSystemAudio() -> Bool {
        guard var snapshot = audioRestoreSnapshot else { return true }
        if snapshot.restore() {
            audioRestoreSnapshot = nil
            return true
        } else {
            audioRestoreSnapshot = snapshot
            appStateLogger.warning("Audio restore skipped because output device changed")
            return false
        }
    }

    private func scheduleSystemAudioRestore(afterAirPods: Bool) {
        guard audioRestoreSnapshot != nil else { return }
        guard afterAirPods else {
            restoreSystemAudio()
            return
        }

        let restoreAudio = { [weak self] in
            guard let self else { return }
            if !self.restoreSystemAudio() {
                self.scheduleSystemAudioRestore(afterAirPods: true)
            }
        }
        unmuteOnDeviceChange = restoreAudio
        unmuteTimeoutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.unmuteOnDeviceChange != nil else { return }
            self.unmuteOnDeviceChange = nil
            self.unmuteTimeoutWork = nil
            restoreAudio()
        }
        unmuteTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    // MARK: - Error Handling

    private func handleError(_ err: Error) {
        let isQuota: Bool = {
            if let te = err as? SPEXTError, case .quotaExceeded = te { return true }
            return false
        }()
        isQuotaExceeded = isQuota
        errorMessage    = err.localizedDescription
        statusMessage   = isQuota ? "Kein Guthaben" : "Fehler"
    }
}
