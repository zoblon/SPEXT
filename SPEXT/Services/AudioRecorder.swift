import AVFoundation
import Combine
import CoreAudio
import Foundation
import OSLog

private let recorderLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "de.Rehkopf.SPEXT",
    category: "Recorder"
)

enum RecorderStartupPolicy {
    enum Event {
        case writableFrames
        case formatChanged
        case formatUnsupported
        case noFrames
        case stopped
    }

    enum Action: Equatable {
        case succeed
        case retry
        case fail
        case cancel
    }

    nonisolated static let maximumAttempts = 3
    nonisolated static let totalBudget: TimeInterval = 8
    nonisolated static let retryDelay: TimeInterval = 0.3
    nonisolated static let deviceVerificationInterval: TimeInterval = 0.025
    nonisolated static let deviceVerificationTimeout: TimeInterval = 0.4

    nonisolated static func noWritableFramesTimeout(isAirPods: Bool, attempt: Int) -> TimeInterval {
        isAirPods && attempt == 1 ? 0.75 : 2.0
    }

    nonisolated static func shouldRetry(attempt: Int, elapsed: TimeInterval) -> Bool {
        attempt < maximumAttempts && elapsed < totalBudget
    }

    nonisolated static func action(attempt: Int, elapsed: TimeInterval, event: Event) -> Action {
        switch event {
        case .writableFrames:
            return .succeed
        case .stopped:
            return .cancel
        case .formatChanged, .formatUnsupported, .noFrames:
            return shouldRetry(attempt: attempt, elapsed: elapsed) ? .retry : .fail
        }
    }
}

enum MicReadinessPolicy {
    nonisolated static func shouldSignalMicReady(
        wroteFormatValidBuffer: Bool
    ) -> Bool {
        wroteFormatValidBuffer
    }
}

struct RecordingStartResult {
    let sessionID: UUID
    let errorMessage: String?
    var succeeded: Bool { errorMessage == nil }
}

struct RecordingResult {
    let sessionID: UUID
    let url: URL?
    let warning: String?
    let errorMessage: String?
    let statistics: RecordingStatistics?
}

struct RecordingStatistics {
    let receivedFrames: Int
    let writtenFrames: Int
    let voicedFrames: Int
    let peakAudioLevel: Float
    let writeFailureSignaled: Bool
    let voicedDuration: TimeInterval
    let audioDuration: TimeInterval
}

class AudioRecorder: ObservableObject {
    @Published var isRecording = false

    /// Current level 0.0–1.0 for the waveform animation
    @Published var audioLevel: Float = 0

    /// true as soon as the recording is writing stably and the microphone is ready
    @Published var isMicReady = false
    @Published var signalWarning = false

    private(set) var lastWarning: String?
    private var segmentURLs: [URL] = []
    private var healthTimer: DispatchSourceTimer?

    private var engine           = AVAudioEngine()
    private var audioFile:       AVAudioFile?
    private var recordingURL:    URL?
    private let recorderQueue = DispatchQueue(label: "de.Rehkopf.SPEXT.AudioRecorder", qos: .userInitiated)
    private let stateLock = NSLock()
    /// Protects only the writer and the segment list. The main thread never takes this lock.
    private let writerLock = NSLock()

    private struct RealtimeState {
        var sessionID = UUID()
        var isRecording = false
        var isWriting = false
        var micReadySignaled = false
        var lastLevelDispatch: TimeInterval = 0
        var receivedFrames = 0
        var writtenFrames = 0
        var voicedFrames = 0
        var peakAudioLevel: Float = 0
        var writeFailureSignaled = false
        var lastBufferAt: TimeInterval = 0
        var lastSpeechAt: TimeInterval = 0
        var voicedDuration: TimeInterval = 0
        var audioDuration: TimeInterval = 0
        var bufferGapDetected = false

        mutating func resetForNewFile() {
            isWriting = false
            micReadySignaled = false
            lastLevelDispatch = 0
            receivedFrames = 0
            writtenFrames = 0
            voicedFrames = 0
            peakAudioLevel = 0
            writeFailureSignaled = false
            lastBufferAt = CACurrentMediaTime()
            lastSpeechAt = lastBufferAt
            voicedDuration = 0
            audioDuration = 0
            bufferGapDetected = false
        }
    }

    private var realtimeState = RealtimeState()

    /// UID of the device the engine is currently warm for
    private var warmDeviceUID: String?

    /// Keeps only non-Bluetooth devices warm after a recording ends.
    private var cooldownWorkItem: DispatchWorkItem?

    /// true if a tap is installed on engine.inputNode
    private var tapInstalled = false

    /// Observer for AVAudioEngineConfigurationChange (fires e.g. on the AirPods HFP switch)
    private var engineConfigObserver: NSObjectProtocol?
    private var configObserverID = UUID()
    private var pendingConfigRestartID: UUID?

    private var currentSessionID = UUID()
    private var engineGeneration: UInt64 = 0
    private var startupBeganAt: TimeInterval = 0
    private var currentStartupAttempt = 0
    private var pendingStartCompletion: ((RecordingStartResult) -> Void)?
    private var pendingStartSessionID: UUID?
    private var startupTerminalDelivered = false
    private var pendingColdRetryID: UUID?
#if SPEXT_RECORDER_TESTS
    // Only the hardware start is replaced in tests; scheduling and error paths are real.
    private var testColdAttempt: ((Int) -> Void)?
    private var testEngineRunning: Bool?
#endif
    private var recordingDeviceUID = ""
    private var recordingDeviceName = "Standard-Mikrofon"
    private var recordingDevice: AudioDevice?
    private(set) var recordingDeviceIsAirPods = false
    private var recordingDeviceHadInputAtStart = true
    private var recordingFormatDescription = "unbekannt"
    private var configChangeCount = 0
    private var engineStartDate: Date = .distantPast

    /// Called when a running recording has to be aborted internally
    /// (e.g. after a failed HFP restart). AppState then hides the HUD and shows an error.
    var onRecordingFailed: ((String) -> Void)?

    var lastError: String?

    static func warmRetentionDuration(for device: AudioDevice?) -> TimeInterval? {
        guard let device else { return 60 }
        if device.isBluetooth { return nil }
        if device.isContinuityLike { return 30 }
        return 60
    }

    private func beginRecordingState() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !realtimeState.isRecording else { return false }
        realtimeState.sessionID = UUID()
        realtimeState.isRecording = true
        realtimeState.resetForNewFile()
        return true
    }

    private func finishRecordingState(resetStats: Bool = true) {
        stateLock.lock()
        realtimeState.isRecording = false
        realtimeState.isWriting = false
        if resetStats {
            realtimeState.resetForNewFile()
        }
        stateLock.unlock()
    }

    private func setWriting(_ isWriting: Bool) {
        stateLock.lock()
        realtimeState.isWriting = isWriting
        stateLock.unlock()
    }

    private func resetRealtimeStats(startWriting: Bool) {
        stateLock.lock()
        realtimeState.resetForNewFile()
        realtimeState.isWriting = startWriting
        stateLock.unlock()
    }

    private func checkStillRecording() -> Bool {
        stateLock.lock()
        let isRecording = realtimeState.isRecording
        stateLock.unlock()
        return isRecording
    }

    private func isCurrentSession(_ id: UUID, requiresRecording: Bool = true) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return realtimeState.sessionID == id && (!requiresRecording || realtimeState.isRecording)
    }

    private func currentWrittenFrames() -> Int {
        stateLock.lock()
        let frames = realtimeState.writtenFrames
        stateLock.unlock()
        return frames
    }

    private func currentWriteFailureSignaled() -> Bool {
        stateLock.lock()
        let failed = realtimeState.writeFailureSignaled
        stateLock.unlock()
        return failed
    }

    private func currentIsWriting() -> Bool {
        stateLock.lock()
        let isWriting = realtimeState.isWriting
        stateLock.unlock()
        return isWriting
    }

    private func nextEngineGeneration() -> UInt64 {
        stateLock.lock()
        engineGeneration &+= 1
        let generation = engineGeneration
        stateLock.unlock()
        return generation
    }

    private func isCurrentEngineGeneration(_ generation: UInt64) -> Bool {
        stateLock.lock()
        let isCurrent = engineGeneration == generation
        stateLock.unlock()
        return isCurrent
    }

    private func snapshotStats(reset: Bool) -> RecordingStatistics {
        stateLock.lock()
        let stats = RecordingStatistics(
            receivedFrames: realtimeState.receivedFrames,
            writtenFrames: realtimeState.writtenFrames,
            voicedFrames: realtimeState.voicedFrames,
            peakAudioLevel: realtimeState.peakAudioLevel,
            writeFailureSignaled: realtimeState.writeFailureSignaled,
            voicedDuration: realtimeState.voicedDuration,
            audioDuration: realtimeState.audioDuration
        )
        if reset {
            realtimeState.resetForNewFile()
        }
        stateLock.unlock()
        return stats
    }

    // MARK: - Start Recording

    /// Starts a new recording on the serial recorder queue.
    /// The completion is called after a successful start or a start failure.
    func startRecording(
        deviceUID: String?,
        knownDevice: AudioDevice? = nil,
        completion: @escaping (RecordingStartResult) -> Void
    ) -> UUID? {
        guard beginRecordingState() else {
            completion(RecordingStartResult(
                sessionID: currentSessionID,
                errorMessage: String(localized: "A recording is already in progress.")
            ))
            return nil
        }

        stateLock.lock()
        let sessionID = realtimeState.sessionID
        stateLock.unlock()

        DispatchQueue.main.async {
            self.isRecording = true
            self.isMicReady = false
            self.audioLevel = 0
        }

        recorderQueue.async { [weak self] in
            guard let self else { return }
            self.pendingStartCompletion = completion
            self.pendingStartSessionID = sessionID
            self.startupTerminalDelivered = false
            self.startRecordingOnRecorderQueue(deviceUID: deviceUID, knownDevice: knownDevice)
        }
        return sessionID
    }

    private func startRecordingOnRecorderQueue(deviceUID: String?, knownDevice: AudioDevice?) {
        let uid = deviceUID ?? AudioDevice.defaultInputUID() ?? ""

        // Take the real device class into account for the system default as well.
        // This fallback runs off the hotkey/main thread.
        let selectedDevice = knownDevice ?? AudioDevice.allAudioDevices().first { $0.id == uid }
        stateLock.lock()
        currentSessionID = realtimeState.sessionID
        stateLock.unlock()
        lastWarning = nil
        lastError = nil
        DispatchQueue.main.async { self.signalWarning = false }
        recordingDeviceUID      = uid
        recordingDevice         = selectedDevice
        recordingDeviceName     = selectedDevice?.name ?? "Standard-Mikrofon"
        recordingDeviceIsAirPods = selectedDevice?.isAirPods ?? false
        recordingDeviceHadInputAtStart = selectedDevice?.hasInput ?? true
        recordingFormatDescription = "unbekannt"
        configChangeCount       = 0

        recorderLogger.info(
            "Recording start session=\(self.currentSessionID.uuidString, privacy: .public) device=\(self.recordingDeviceName, privacy: .public) airPods=\(self.recordingDeviceIsAirPods, privacy: .public) hadInputAtStart=\(self.recordingDeviceHadInputAtStart, privacy: .public)"
        )

        // ── Warm path: engine is already running for the same device ────────
        // HFP is already active → no connection delay, ready to record immediately.
        // (There is no warm path for AirPods: the engine is stopped right after every
        //  BT recording to avoid artifacts when falling back to A2DP.)
        if engine.isRunning && warmDeviceUID == uid {
            let format = engine.inputNode.outputFormat(forBus: 0)
            recordingFormatDescription = Self.describe(format: format)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                failStartup(String(localized: "Microphone format invalid."))
                return
            }
            writerLock.lock()
            let prepared = prepareNewFile(format: format)
            writerLock.unlock()
            guard prepared else {
                failStartup(lastError ?? String(localized: "Audio file could not be created."))
                return
            }

            cancelCooldown()
            resetRealtimeStats(startWriting: true)
            lastError          = nil

            // Set isMicReady immediately (HFP already active, no handshake delay)
            recorderLogger.info(
                "Warm engine reused session=\(self.currentSessionID.uuidString, privacy: .public) device=\(self.recordingDeviceName, privacy: .public)"
            )
            DispatchQueue.main.async { self.isMicReady = true }
            startHealthMonitoring()
            finishStart(errorMessage: nil, exposeError: false)
            return
        }

        // ── Cold path: set up the engine in cancellable steps ───────────────
        cancelCooldown()
        teardownEngine()
        warmDeviceUID = uid
        startupBeganAt = CACurrentMediaTime()
        startColdAttempt(attempt: 1, uid: uid)
    }

    private func startColdAttempt(attempt: Int, uid: String) {
        guard checkStillRecording(), !startupTerminalDelivered else {
            finishStart(errorMessage: String(localized: "Recording was ended."), exposeError: false)
            return
        }

        let elapsed = CACurrentMediaTime() - startupBeganAt
        guard attempt <= RecorderStartupPolicy.maximumAttempts,
              elapsed < RecorderStartupPolicy.totalBudget else {
            failStartup(String(localized: "Microphone format is not supported or not ready yet."))
            return
        }

#if SPEXT_RECORDER_TESTS
        if let testColdAttempt {
            testColdAttempt(attempt)
            return
        }
#endif

        invalidateCurrentEngineForRetry()
        currentStartupAttempt = attempt
        let phaseStarted = CACurrentMediaTime()
        engine = AVAudioEngine()
        let generation = nextEngineGeneration()
        _ = engine.inputNode
        logStartupPhase("engine-created", attempt: attempt, generation: generation, beganAt: phaseStarted)

        if !uid.isEmpty {
            let setStarted = CACurrentMediaTime()
            guard setInputDevice(uid: uid) else {
                retryColdStart(attempt: attempt, uid: uid, message: String(localized: "Microphone could not be selected"))
                return
            }
            logStartupPhase("device-set", attempt: attempt, generation: generation, beganAt: setStarted)
            guard let expectedID = AudioDevice.coreAudioID(forUID: uid) else {
                retryColdStart(attempt: attempt, uid: uid, message: String(localized: "Microphone could not be resolved"))
                return
            }
            verifySelectedDevice(
                expectedID,
                deadline: CACurrentMediaTime() + RecorderStartupPolicy.deviceVerificationTimeout,
                attempt: attempt,
                uid: uid,
                generation: generation
            )
            return
        }

        startCurrentGraph(attempt: attempt, uid: uid, generation: generation)
    }

    private func verifySelectedDevice(
        _ expectedID: AudioDeviceID,
        deadline: TimeInterval,
        attempt: Int,
        uid: String,
        generation: UInt64
    ) {
        guard checkStillRecording(), isCurrentEngineGeneration(generation) else { return }
        if currentInputDeviceID() == expectedID {
            startCurrentGraph(attempt: attempt, uid: uid, generation: generation)
            return
        }
        guard CACurrentMediaTime() < deadline else {
            retryColdStart(attempt: attempt, uid: uid, message: String(localized: "Microphone selection was not confirmed"))
            return
        }
        recorderQueue.asyncAfter(deadline: .now() + RecorderStartupPolicy.deviceVerificationInterval) { [weak self] in
            self?.verifySelectedDevice(
                expectedID,
                deadline: deadline,
                attempt: attempt,
                uid: uid,
                generation: generation
            )
        }
    }

    private func startCurrentGraph(attempt: Int, uid: String, generation: UInt64) {
        guard checkStillRecording(), isCurrentEngineGeneration(generation) else { return }
        let inputNode = engine.inputNode
        let nodeFormat = inputNode.outputFormat(forBus: 0)
        let hardwareFormat = uid.isEmpty ? nil : Self.hardwareInputFormat(uid: uid)
        let tapFormat = Self.tapFormat(nodeFormat: nodeFormat, hardwareFormat: hardwareFormat)
        recordingFormatDescription = Self.describe(format: nodeFormat)
        recorderLogger.info(
            "Startup formats session=\(self.currentSessionID.uuidString, privacy: .public) attempt=\(attempt, privacy: .public) generation=\(generation, privacy: .public) node=\(Self.describe(format: nodeFormat), privacy: .public) hardware=\(hardwareFormat.map(Self.describe(format:)) ?? "unavailable", privacy: .public)"
        )
        if let tapFormat {
            recorderLogger.info(
                "Aligning input tap with hardware session=\(self.currentSessionID.uuidString, privacy: .public) attempt=\(attempt, privacy: .public) format=\(Self.describe(format: tapFormat), privacy: .public)"
            )
        }

        cleanupRecordingFile()
        resetRealtimeStats(startWriting: true)
        installTap(on: inputNode, generation: generation, format: tapFormat)

        let prepareStarted = CACurrentMediaTime()
        registerEngineConfigObserver()
        engineStartDate = Date()
        engine.prepare()
        logStartupPhase("prepare", attempt: attempt, generation: generation, beganAt: prepareStarted)
        do {
            let startBegan = CACurrentMediaTime()
            try engine.start()
            logStartupPhase("engine-start", attempt: attempt, generation: generation, beganAt: startBegan)
        } catch {
            let nsError = error as NSError
            recorderLogger.warning(
                "Engine start failed session=\(self.currentSessionID.uuidString, privacy: .public) attempt=\(attempt, privacy: .public) generation=\(generation, privacy: .public) code=\(nsError.code, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            let message = nsError.code == Int(kAudioUnitErr_FormatNotSupported)
                ? String(localized: "The current microphone format is not supported. The connection is being re-established.")
                : error.localizedDescription
            retryColdStart(attempt: attempt, uid: uid, message: message)
            return
        }

        let timeout = RecorderStartupPolicy.noWritableFramesTimeout(
            isAirPods: recordingDeviceIsAirPods,
            attempt: attempt
        )
        recorderQueue.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, self.isCurrentEngineGeneration(generation),
                  self.checkStillRecording(), !self.startupTerminalDelivered else { return }
            if self.currentWrittenFrames() > 0 {
                self.completeSuccessfulStart()
            } else if self.currentWriteFailureSignaled() {
                self.failStartup(String(localized: "Audio file could not be written."))
            } else {
                recorderLogger.warning(
                    "Engine started without writable frames session=\(self.currentSessionID.uuidString, privacy: .public) attempt=\(attempt, privacy: .public) generation=\(generation, privacy: .public) timeout=\(timeout, privacy: .public)"
                )
                self.retryColdStart(attempt: attempt, uid: uid, message: String(localized: "Microphone delivers no audio data"))
            }
        }
    }

    private func retryColdStart(attempt: Int, uid: String, message: String) {
        guard checkStillRecording(), !startupTerminalDelivered,
              pendingColdRetryID == nil else { return }
        let elapsed = CACurrentMediaTime() - startupBeganAt
        guard RecorderStartupPolicy.shouldRetry(attempt: attempt, elapsed: elapsed) else {
            failStartup(message)
            return
        }
        setWriting(false)
        let retryID = UUID()
        pendingColdRetryID = retryID
        let sessionID = currentSessionID
        let generation = engineGeneration
        let nextAttempt = attempt + 1
        recorderQueue.asyncAfter(deadline: .now() + RecorderStartupPolicy.retryDelay) { [weak self] in
            guard let self, self.pendingColdRetryID == retryID,
                  self.isCurrentSession(sessionID),
                  self.isCurrentEngineGeneration(generation) else { return }
            self.pendingColdRetryID = nil
            self.startColdAttempt(attempt: nextAttempt, uid: uid)
        }
    }

    private func completeSuccessfulStart() {
        guard !startupTerminalDelivered else { return }
        lastError = nil
        startHealthMonitoring()
        finishStart(errorMessage: nil, exposeError: false)
    }

    private func failStartup(_ message: String) {
        guard !startupTerminalDelivered else { return }
        lastError = message
        finishRecordingState()
        teardownEngine()
        cleanupRecordingFile()
        DispatchQueue.main.async { self.isRecording = false }
        recorderLogger.error(
            "Microphone start failed session=\(self.currentSessionID.uuidString, privacy: .public) message=\(message, privacy: .public)"
        )
        finishStart(errorMessage: message, exposeError: true)
    }

    private func finishStart(errorMessage: String?, exposeError: Bool) {
        guard !startupTerminalDelivered,
              let completion = pendingStartCompletion,
              let sessionID = pendingStartSessionID else { return }
        startupTerminalDelivered = true
        pendingColdRetryID = nil
        pendingStartCompletion = nil
        pendingStartSessionID = nil
        let result = RecordingStartResult(
            sessionID: sessionID,
            errorMessage: exposeError ? errorMessage : nil
        )
        DispatchQueue.main.async { completion(result) }
    }

    private func logStartupPhase(_ phase: String, attempt: Int, generation: UInt64, beganAt: TimeInterval) {
        let milliseconds = (CACurrentMediaTime() - beganAt) * 1_000
        recorderLogger.info(
            "Startup phase session=\(self.currentSessionID.uuidString, privacy: .public) attempt=\(attempt, privacy: .public) generation=\(generation, privacy: .public) phase=\(phase, privacy: .public) milliseconds=\(milliseconds, privacy: .public)"
        )
    }

    private func invalidateCurrentEngineForRetry() {
        if let observer = engineConfigObserver {
            NotificationCenter.default.removeObserver(observer)
            engineConfigObserver = nil
        }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine.isRunning { engine.stop() }
        _ = nextEngineGeneration()
        writerLock.lock()
        audioFile = nil
        writerLock.unlock()
    }

    /// Reads the ACTUAL hardware input format of a CoreAudio device
    /// (`kAudioDevicePropertyStreamFormat` in the input scope).
    ///
    /// This is the only reliable source for the real hardware format.
    /// `AVAudioInputNode.outputFormat(forBus:)`, in contrast, returns the ENGINE CLIENT format,
    /// which after a device switch can stay stuck on the old value (e.g. the 48000 Hz
    /// engine default) for a while, even though the new device already runs at a different rate.
    /// Passing the wrong value to installTap crashes the app with an NSException.
    private static func hardwareInputFormat(uid: String) -> AVAudioFormat? {
        guard let deviceID = AudioDevice.coreAudioID(forUID: uid) else { return nil }
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope:    kAudioDevicePropertyScopeInput,
            mElement:  kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &asbd)
        guard status == noErr, asbd.mSampleRate > 0, asbd.mChannelsPerFrame > 0 else {
            return nil
        }
        return AVAudioFormat(streamDescription: &asbd)
    }

    nonisolated private static func describe(format: AVAudioFormat) -> String {
        "\(Int(format.sampleRate)) Hz, \(format.channelCount) ch"
    }

    /// After a Bluetooth profile switch the InputNode may still report its old
    /// client format (typically 48 kHz), although the hardware is already running
    /// at 24 kHz. A tap without an explicit format then adopts the
    /// stale format and engine.start() fails with -10868.
    /// The tap therefore receives a canonical Float32 client format with the current
    /// hardware values when the rate/channel count really changed.
    private static func tapFormat(
        nodeFormat: AVAudioFormat,
        hardwareFormat: AVAudioFormat?
    ) -> AVAudioFormat? {
        guard let hardwareFormat,
              hardwareFormat.sampleRate > 0,
              hardwareFormat.channelCount > 0,
              (nodeFormat.sampleRate != hardwareFormat.sampleRate
                || nodeFormat.channelCount != hardwareFormat.channelCount)
        else { return nil }

        return AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: hardwareFormat.sampleRate,
            channels: hardwareFormat.channelCount,
            interleaved: false
        )
    }

    // MARK: - Stop Recording

    /// Called from the main thread (AppState.stopAndTranscribe).
    func stopRecording(completion: @escaping (RecordingResult) -> Void) {
        assert(Thread.isMainThread, "stopRecording muss auf dem Main-Thread laufen")

        stateLock.lock()
        let sessionID = realtimeState.sessionID
        let wasRecording = realtimeState.isRecording
        realtimeState.isRecording = false
        realtimeState.isWriting = false
        realtimeState.micReadySignaled = false
        realtimeState.lastLevelDispatch = 0
        stateLock.unlock()

        guard wasRecording || isRecording else {
            completion(RecordingResult(
                sessionID: sessionID,
                url: nil,
                warning: nil,
                errorMessage: nil,
                statistics: nil
            ))
            return
        }

        isRecording = false
        isMicReady = false
        audioLevel = 0

        recorderQueue.async { [weak self] in
            guard let self else { return }
            self.finishStart(errorMessage: String(localized: "Recording was ended."), exposeError: false)

            self.writerLock.lock()
            self.audioFile = nil
            self.writerLock.unlock()

            self.healthTimer?.cancel()
            self.healthTimer = nil
            let segments = self.segmentURLs
            self.segmentURLs = []
            let url = self.recordingURL
            self.recordingURL = nil
            defer {
                for segment in segments { try? FileManager.default.removeItem(at: segment) }
            }

            let now = CACurrentMediaTime()
            self.stateLock.lock()
            let stalled = self.realtimeState.bufferGapDetected || RecordingHealthPolicy.hasStalled(now: now, lastBufferAt: self.realtimeState.lastBufferAt)
            let quietTail = self.realtimeState.voicedFrames > 0 && RecordingHealthPolicy.needsSignalWarning(
                now: now, lastSpeechAt: self.realtimeState.lastSpeechAt)
            self.stateLock.unlock()
            let duration = self.snapshotStats(reset: false).audioDuration
            let stats = self.snapshotStats(reset: true)
            let fileSize: Int64
            if let url,
               let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? NSNumber {
                fileSize = size.int64Value
            } else {
                fileSize = 0
            }

            recorderLogger.info(
                "Recording stop session=\(self.currentSessionID.uuidString, privacy: .public) duration=\(duration, privacy: .public) receivedFrames=\(stats.receivedFrames, privacy: .public) writtenFrames=\(stats.writtenFrames, privacy: .public) voicedFrames=\(stats.voicedFrames, privacy: .public) peakLevel=\(stats.peakAudioLevel, privacy: .public) fileSize=\(fileSize, privacy: .public) format=\(self.recordingFormatDescription, privacy: .public) configChanges=\(self.configChangeCount, privacy: .public)"
            )

            let resultURL: URL?
            if let url {
                if stalled || stats.writeFailureSignaled || self.pendingConfigRestartID != nil {
                    self.lastError = String(localized: "The microphone connection was interrupted. Please record again or choose a different microphone.")
                    resultURL = nil
                } else if duration < 1.0 || stats.writtenFrames == 0 {
                    recorderLogger.warning(
                        "Recording discarded session=\(self.currentSessionID.uuidString, privacy: .public) duration=\(duration, privacy: .public) receivedFrames=\(stats.receivedFrames, privacy: .public) writtenFrames=\(stats.writtenFrames, privacy: .public)"
                    )
                    try? FileManager.default.removeItem(at: url)
                    resultURL = nil
                } else if !RecordingQuality.hasMeaningfulSpeech(
                            peakAudioLevel: stats.peakAudioLevel,
                            voicedFrames: Int(stats.voicedDuration * 24_000),
                            totalFrames: Int(stats.audioDuration * 24_000)) {
                    // Silence / no real speech signal (e.g. key held, but nothing said).
                    // Intentionally NO error message and NO upload: otherwise transcription models would
                    // hallucinate plausible-sounding but invented sentences from silence ("OpenAI has
                    // announced an update…") or output dictionary words. As with the short abort
                    // (<1s), the recording is simply discarded silently → AppState returns to "Ready".
                    self.lastError = nil
                    recorderLogger.warning(
                        "Recording discarded because no speech detected session=\(self.currentSessionID.uuidString, privacy: .public) peakLevel=\(stats.peakAudioLevel, privacy: .public) voicedFrames=\(stats.voicedFrames, privacy: .public) writtenFrames=\(stats.writtenFrames, privacy: .public)"
                    )
                    try? FileManager.default.removeItem(at: url)
                    resultURL = nil
                } else if stats.receivedFrames != stats.writtenFrames {
                    self.lastError = String(localized: "Recording was written incompletely – please record again.")
                    recorderLogger.error(
                        "Recording discarded because frame counters differ session=\(self.currentSessionID.uuidString, privacy: .public) receivedFrames=\(stats.receivedFrames, privacy: .public) writtenFrames=\(stats.writtenFrames, privacy: .public)"
                    )
                    try? FileManager.default.removeItem(at: url)
                    resultURL = nil
                } else {
                    do {
                        resultURL = try RecordingAssembler.export(segments: segments)
                        self.lastError = nil
                        if quietTail {
                            self.lastWarning = String(localized: "For several seconds at the end of the recording, no clear speech signal arrived. Please check the text before pasting.")
                        }
                    } catch {
                        self.lastError = String(localized: "Recording could not be finalized: \(error.localizedDescription)")
                        resultURL = nil
                    }
                }
            } else {
                resultURL = nil
            }

            recorderLogger.info("Recording file finalized session=\(self.currentSessionID.uuidString, privacy: .public)")
            completion(RecordingResult(
                sessionID: sessionID,
                url: resultURL,
                warning: self.lastWarning,
                errorMessage: self.lastError,
                statistics: stats
            ))
            self.scheduleWarmTeardownAfterStop()
        }
    }

    // MARK: - Install Tap

    /// Installs the audio tap on the InputNode.
    /// Encapsulates level calculation, isMicReady signalling and file writing.
    private func installTap(
        on inputNode: AVAudioInputNode,
        generation: UInt64,
        format: AVAudioFormat? = nil
    ) {
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }

            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else { return }
            var measuredLevel: Float?
            if let channels = buffer.floatChannelData {
                var strongest: Float = 0
                for channel in 0..<Int(buffer.format.channelCount) {
                    var sum: Float = 0
                    for i in 0..<frameCount {
                        let sample = channels[channel][i * buffer.stride]
                        sum += sample * sample
                    }
                    strongest = max(strongest, sqrt(sum / Float(frameCount)))
                }
                measuredLevel = min(strongest * 25, 1.0)
            }

            var shouldSignalReady = false
            var levelForDispatch: Float?
            var writeError: Error?
            var shouldReportWriteFailure = false

            self.stateLock.lock()
            let sessionID = self.realtimeState.sessionID
            guard self.engineGeneration == generation, self.realtimeState.isWriting else {
                self.stateLock.unlock()
                return
            }
            self.realtimeState.receivedFrames += frameCount
            if let measuredLevel {
                if measuredLevel > self.realtimeState.peakAudioLevel {
                    self.realtimeState.peakAudioLevel = measuredLevel
                }
                if measuredLevel >= RecordingQuality.speechLevelThreshold {
                    self.realtimeState.voicedFrames += frameCount
                    self.realtimeState.voicedDuration += Double(frameCount) / buffer.format.sampleRate
                    self.realtimeState.lastSpeechAt = CACurrentMediaTime()
                }
                let now = CACurrentMediaTime()
                if now - self.realtimeState.lastLevelDispatch >= 0.033 {
                    self.realtimeState.lastLevelDispatch = now
                    levelForDispatch = measuredLevel
                }
            }

            let now = CACurrentMediaTime()
            if self.realtimeState.writtenFrames > 0,
               RecordingHealthPolicy.hasStalled(now: now, lastBufferAt: self.realtimeState.lastBufferAt) {
                self.realtimeState.bufferGapDetected = true
            }
            self.stateLock.unlock()

            self.writerLock.lock()
            do {
                if self.audioFile == nil {
                    self.recordingFormatDescription = Self.describe(format: buffer.format)
                    guard self.prepareNewFile(format: buffer.format) else {
                        throw NSError(
                            domain: "SPEXT.AudioWriter",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: self.lastError ?? String(localized: "Audio file could not be created")]
                        )
                    }
                }
                guard let audioFile = self.audioFile,
                      Self.formatsMatch(buffer.format, audioFile.processingFormat) else {
                    self.writerLock.unlock()
                    self.setWriting(false)
                    self.recorderQueue.async { [weak self] in
                        guard let self, self.isCurrentEngineGeneration(generation),
                              self.isCurrentSession(sessionID) else { return }
                        self.handleEngineConfigChange(bufferFormatChanged: true)
                    }
                    return
                }
                try audioFile.write(from: buffer)
                self.writerLock.unlock()

                self.stateLock.lock()
                guard self.engineGeneration == generation,
                      self.realtimeState.sessionID == sessionID else {
                    self.stateLock.unlock()
                    return
                }
                self.realtimeState.writtenFrames += frameCount
                self.realtimeState.lastBufferAt = CACurrentMediaTime()
                self.realtimeState.audioDuration += Double(frameCount) / buffer.format.sampleRate
                if !self.realtimeState.micReadySignaled {
                    let canSignalReady = MicReadinessPolicy.shouldSignalMicReady(wroteFormatValidBuffer: true)
                    if canSignalReady {
                        self.realtimeState.micReadySignaled = true
                        shouldSignalReady = true
                    }
                }
                self.stateLock.unlock()
            } catch {
                self.writerLock.unlock()
                self.stateLock.lock()
                if !self.realtimeState.writeFailureSignaled {
                    self.realtimeState.writeFailureSignaled = true
                    self.realtimeState.isWriting = false
                    writeError = error
                    shouldReportWriteFailure = true
                }
                self.stateLock.unlock()
            }

            if shouldSignalReady {
                recorderLogger.info(
                    "Mic ready buffer received session=\(self.currentSessionID.uuidString, privacy: .public)"
                )
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isCurrentSession(sessionID) else { return }
                    self.isMicReady = true
                    recorderLogger.info(
                        "Mic ready session=\(self.currentSessionID.uuidString, privacy: .public)"
                    )
                }
                self.recorderQueue.async { [weak self] in
                    guard let self, self.isCurrentEngineGeneration(generation),
                          self.isCurrentSession(sessionID) else { return }
                    self.completeSuccessfulStart()
                }
            }

            if let levelForDispatch {
                DispatchQueue.main.async {
                    guard self.isCurrentSession(sessionID) else { return }
                    self.audioLevel = levelForDispatch
                }
            }

            if shouldReportWriteFailure, let writeError {
                self.reportAudioWriteFailure(writeError, sessionID: sessionID)
            }
        }
        tapInstalled = true
    }

    nonisolated private static func formatsMatch(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs.sampleRate == rhs.sampleRate
            && lhs.channelCount == rhs.channelCount
            && lhs.commonFormat == rhs.commonFormat
            && lhs.isInterleaved == rhs.isInterleaved
    }

    private func reportAudioWriteFailure(_ error: Error, sessionID: UUID) {
        recorderLogger.error(
            "Audio write failed session=\(self.currentSessionID.uuidString, privacy: .public) device=\(self.recordingDeviceName, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
        )
        recorderQueue.async { [weak self] in
            guard let self, self.isCurrentSession(sessionID) else { return }
            self.failOngoingRecording(
                message: String(localized: "The audio file could not be written completely during recording. Please record again.")
            )
        }
    }

    // MARK: - Engine Configuration Change (AirPods HFP Switch)

    /// Registers an observer for AVAudioEngineConfigurationChange.
    /// Called after every successful engine start.
    private func registerEngineConfigObserver() {
        if let existing = engineConfigObserver {
            NotificationCenter.default.removeObserver(existing)
        }
        configObserverID = UUID()
        let observerID = configObserverID
        let observedEngine = engine
        engineConfigObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self, weak observedEngine] _ in
            self?.recorderQueue.async {
                guard let self, let observedEngine, self.engine === observedEngine,
                      self.configObserverID == observerID else { return }
                self.handleEngineConfigChange()
            }
        }
    }

    /// Called when CoreAudio reconfigures the audio hardware –
    /// typically on the AirPods switch A2DP → HFP (microphone gets enabled).
    /// The running engine stops automatically in that case; we restart it.
    private func handleEngineConfigChange(bufferFormatChanged: Bool = false) {
        var running = engine.isRunning
#if SPEXT_RECORDER_TESTS
        running = testEngineRunning ?? running
#endif
        recorderLogger.info("Configuration observed running=\(running, privacy: .public) frames=\(self.currentWrittenFrames(), privacy: .public) startup=\(self.pendingStartCompletion != nil, privacy: .public) bufferFormatChanged=\(bufferFormatChanged, privacy: .public)")
        // Device set/start can enqueue an already outdated notification.
        // Do not tear down an engine that is running by now: the first frames and
        // the watchdog verify the stream. A real tap format error remains mandatory.
        if running && !bufferFormatChanged {
            recorderLogger.info("Configuration notification ignored; engine already running")
            return
        }
        guard checkStillRecording() else {
            // Engine in warm mode (between two recordings): CoreAudio has stopped it.
            // Shut it down completely so the next start goes cleanly through the cold path.
            recorderLogger.info(
                "Configuration change in warm mode session=\(self.currentSessionID.uuidString, privacy: .public); tearing down engine"
            )
            teardownEngine()
            return
        }

        guard pendingConfigRestartID == nil, pendingColdRetryID == nil else { return }
        configChangeCount += 1
        recorderLogger.warning(
            "Configuration change session=\(self.currentSessionID.uuidString, privacy: .public) count=\(self.configChangeCount, privacy: .public) device=\(self.recordingDeviceName, privacy: .public) airPods=\(self.recordingDeviceIsAirPods, privacy: .public)"
        )

        // During startup the startup controller handles the change.
        // This lets the notification be processed between two steps instead of
        // waiting behind a polling loop on the same queue.
        // Continuity/iPhone can also change its format when it is connected.
        // Before the first buffer this applies regardless of the device class.
        if pendingStartCompletion != nil, currentWrittenFrames() == 0 {
            retryColdStart(
                attempt: max(currentStartupAttempt, 1),
                uid: warmDeviceUID ?? "",
                message: String(localized: "Microphone format changed during startup")
            )
            return
        }

        guard (recordingDeviceIsAirPods || recordingDevice?.isContinuityLike == true),
              configChangeCount <= 4 else {
            failOngoingRecording(
                message: String(localized: "The microphone was reconfigured during recording. Please record again.")
            )
            return
        }

        // If buffers already exist, preserve the segments via recovery.
        if pendingStartCompletion != nil { completeSuccessfulStart() }

        // Unregister the observer: no loop if the restart itself triggers a change.
        // Registered again after a successful restart in restartEngineAfterConfigChange.
        if let observer = engineConfigObserver {
            NotificationCenter.default.removeObserver(observer)
            engineConfigObserver = nil
        }

        setWriting(false)
        healthTimer?.cancel()
        healthTimer = nil
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        stateLock.lock()
        let hadSpeech = realtimeState.voicedFrames > 0
        realtimeState.micReadySignaled = false
        stateLock.unlock()
        if hadSpeech {
            lastWarning = String(localized: "The microphone connection was re-established during recording. Please check the text for missing words.")
        }

        // Show dots – the HFP connection is being re-established
        DispatchQueue.main.async { self.isMicReady = false; self.audioLevel = 0 }

        // Only one recovery per connection change; delayed attempts are bound to this ID.
        let restartID = UUID()
        pendingConfigRestartID = restartID

        // Short pause: let the CoreAudio stack settle after the format change
        recorderQueue.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self,
                  self.checkStillRecording(),
                  self.pendingConfigRestartID == restartID else { return }
            self.restartEngineAfterConfigChange(attempt: 1)
        }
    }

    /// Restarts the engine after a config change in bounded, non-blocking
    /// steps. Existing segments are preserved; the next writer is created
    /// from the buffer format that actually arrives.
    private func restartEngineAfterConfigChange(attempt: Int) {
        guard checkStillRecording(), pendingConfigRestartID != nil else { return }

        let uid = warmDeviceUID ?? ""

        // The engine has already been stopped by the config change – check to be safe.
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }

        let generation = nextEngineGeneration()
        let inputNode = engine.inputNode
        if !uid.isEmpty, !setInputDevice(uid: uid) {
            guard attempt < 4 else {
                recorderLogger.error(
                    "Input device selection failed after config change session=\(self.currentSessionID.uuidString, privacy: .public) attempt=\(attempt, privacy: .public)"
                )
                failOngoingRecording(message: String(localized: "Microphone could not be selected – please try again."))
                return
            }
            recorderLogger.warning(
                "Input device not selected after config change session=\(self.currentSessionID.uuidString, privacy: .public) attempt=\(attempt, privacy: .public)"
            )
            let recoveryID = pendingConfigRestartID
            recorderQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.checkStillRecording(), self.pendingConfigRestartID == recoveryID else { return }
                self.restartEngineAfterConfigChange(attempt: attempt + 1)
            }
            return
        }

        writerLock.lock()
        audioFile = nil
        writerLock.unlock()

        stateLock.lock()
        realtimeState.micReadySignaled = false
        realtimeState.lastBufferAt = CACurrentMediaTime()
        realtimeState.lastSpeechAt = realtimeState.lastBufferAt
        realtimeState.isWriting = realtimeState.isRecording
        stateLock.unlock()
        let nodeFormat = inputNode.outputFormat(forBus: 0)
        let hardwareFormat = uid.isEmpty ? nil : Self.hardwareInputFormat(uid: uid)
        let tapFormat = Self.tapFormat(nodeFormat: nodeFormat, hardwareFormat: hardwareFormat)
        if let tapFormat {
            recorderLogger.info(
                "Aligning recovery tap with hardware session=\(self.currentSessionID.uuidString, privacy: .public) attempt=\(attempt, privacy: .public) format=\(Self.describe(format: tapFormat), privacy: .public)"
            )
        }
        installTap(on: inputNode, generation: generation, format: tapFormat)

        do {
            recorderLogger.info(
                "Engine restart begin after config change session=\(self.currentSessionID.uuidString, privacy: .public) attempt=\(attempt, privacy: .public)"
            )
            engineStartDate = Date()
            registerEngineConfigObserver()
            engine.prepare()
            try engine.start()
            pendingConfigRestartID = nil
            startHealthMonitoring()
            recorderLogger.info(
                "Engine restarted after AirPods config change session=\(self.currentSessionID.uuidString, privacy: .public) generation=\(generation, privacy: .public)"
            )
        } catch {
            setWriting(false)
            lastError = String(localized: "Engine restart failed: \(error.localizedDescription)")
            recorderLogger.error(
                "Engine restart failed after config change session=\(self.currentSessionID.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            if tapInstalled {
                inputNode.removeTap(onBus: 0)
                tapInstalled = false
            }
            guard attempt < 4 else {
                failOngoingRecording(message: lastError ?? String(localized: "Engine restart failed."))
                return
            }
            let recoveryID = pendingConfigRestartID
            recorderQueue.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self, self.checkStillRecording(),
                      self.pendingConfigRestartID == recoveryID else { return }
                self.restartEngineAfterConfigChange(attempt: attempt + 1)
            }
        }
    }

    /// Shared error path for internal recording aborts (config change errors).
    /// Cleans up engine/file and signals AppState via onRecordingFailed.
    private func failOngoingRecording(message: String) {
        let sessionID = currentSessionID
        lastError = message
        finishRecordingState()
        teardownEngine()
        cleanupRecordingFile()
        // Every abort must also complete a start that is still pending.
        finishStart(errorMessage: message, exposeError: true)
        DispatchQueue.main.async {
            guard self.isCurrentSession(sessionID, requiresRecording: false) else { return }
            self.isRecording = false
            self.isMicReady  = false
            self.audioLevel  = 0
            self.onRecordingFailed?(message)
        }
    }

    private func startHealthMonitoring() {
        healthTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: recorderQueue)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
        let sessionID = currentSessionID
        var lastLoggedAt = CACurrentMediaTime()
        timer.setEventHandler { [weak self] in
            guard let self, self.isCurrentSession(sessionID), self.pendingConfigRestartID == nil else { return }
            let now = CACurrentMediaTime()
            self.stateLock.lock()
            let stalled = self.realtimeState.bufferGapDetected || RecordingHealthPolicy.hasStalled(now: now, lastBufferAt: self.realtimeState.lastBufferAt)
            let quiet = RecordingHealthPolicy.needsSignalWarning(now: now, lastSpeechAt: self.realtimeState.lastSpeechAt)
            self.stateLock.unlock()
            if stalled {
                recorderLogger.error("Recording stream stalled session=\(self.currentSessionID.uuidString, privacy: .public)")
                self.failOngoingRecording(message: String(localized: "The microphone no longer delivers audio data. Please record again or choose a different microphone."))
                return
            }
            if now - lastLoggedAt >= 5 {
                let stats = self.snapshotStats(reset: false)
                recorderLogger.info("Recording health session=\(sessionID.uuidString, privacy: .public) audioSeconds=\(stats.audioDuration, privacy: .public) voicedFrames=\(stats.voicedFrames, privacy: .public) weakSignal=\(quiet, privacy: .public)")
                lastLoggedAt = now
            }
            DispatchQueue.main.async {
                guard self.isCurrentSession(sessionID) else { return }
                self.signalWarning = quiet
            }
        }
        healthTimer = timer
        timer.resume()
    }

    // MARK: - Helpers

    private func prepareNewFile(format: AVAudioFormat) -> Bool {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("caf")

        do {
            var settings = format.settings
            settings[AVLinearPCMIsNonInterleaved] = false
            audioFile = try AVAudioFile(forWriting: url, settings: settings)
            recordingURL = url
            segmentURLs.append(url)
            recorderLogger.info(
                "Prepared recording file session=\(self.currentSessionID.uuidString, privacy: .public) format=\(self.recordingFormatDescription, privacy: .public)"
            )
            return true
        } catch {
            lastError = String(localized: "File error: \(error.localizedDescription)")
            recorderLogger.error(
                "Preparing recording file failed session=\(self.currentSessionID.uuidString, privacy: .public) format=\(self.recordingFormatDescription, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    /// Closes and deletes the current temporary recording file.
    private func cleanupRecordingFile() {
        writerLock.lock()
        audioFile = nil
        for url in segmentURLs { try? FileManager.default.removeItem(at: url) }
        segmentURLs = []
        recordingURL = nil
        writerLock.unlock()
    }

    private func cancelCooldown() {
        cooldownWorkItem?.cancel()
        cooldownWorkItem = nil
    }

    private func scheduleWarmTeardownAfterStop() {
        cancelCooldown()
        guard let retention = Self.warmRetentionDuration(for: recordingDevice) else {
            recorderLogger.info(
                "Warm retention skipped session=\(self.currentSessionID.uuidString, privacy: .public) device=\(self.recordingDeviceName, privacy: .public)"
            )
            teardownEngine()
            return
        }

        var work: DispatchWorkItem!
        work = DispatchWorkItem { [weak self] in
            guard let self, !work.isCancelled else { return }
            recorderLogger.info(
                "Warm retention expired session=\(self.currentSessionID.uuidString, privacy: .public) seconds=\(retention, privacy: .public)"
            )
            self.teardownEngine()
        }
        cooldownWorkItem = work
        recorderLogger.info(
            "Warm retention scheduled session=\(self.currentSessionID.uuidString, privacy: .public) seconds=\(retention, privacy: .public)"
        )
        recorderQueue.asyncAfter(deadline: .now() + retention, execute: work)
    }

    private func teardownEngine() {
        pendingColdRetryID = nil
        pendingConfigRestartID = nil
        configObserverID = UUID()
        healthTimer?.cancel()
        healthTimer = nil
        if let observer = engineConfigObserver {
            NotificationCenter.default.removeObserver(observer)
            engineConfigObserver = nil
        }
        cancelCooldown()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine.isRunning { engine.stop() }
        _ = nextEngineGeneration()
        warmDeviceUID = nil
    }

    // MARK: - Set Device (CoreAudio)

    @discardableResult
    private func setInputDevice(uid: String) -> Bool {
        guard let deviceID = AudioDevice.coreAudioID(forUID: uid),
              let unit     = engine.inputNode.audioUnit else { return false }

        var id = deviceID
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            // Typically: 2003332927 = "who?" = kAudioHardwareUnknownPropertyError,
            // happens when the AudioUnit is in the middle of a config change.
            // Not fatal for the overall flow: callers try again via retry.
            recorderLogger.warning(
                "setInputDevice failed uid=\(uid, privacy: .public) status=\(status, privacy: .public)"
            )
            return false
        }

        return true
    }

    private func currentInputDeviceID() -> AudioDeviceID? {
        guard let unit = engine.inputNode.audioUnit else { return nil }
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioUnitGetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            &size
        )
        return status == noErr && id != 0 ? id : nil
    }
}

#if SPEXT_RECORDER_TESTS
extension AudioRecorder {
    func testBeginStartup(completion: @escaping (RecordingStartResult) -> Void,
                          attempt: @escaping (Int) -> Void) -> UUID {
        recorderQueue.sync {
            precondition(beginRecordingState())
            currentSessionID = realtimeState.sessionID
            pendingStartSessionID = currentSessionID
            pendingStartCompletion = completion
            startupTerminalDelivered = false
            startupBeganAt = CACurrentMediaTime()
            currentStartupAttempt = 1
            configChangeCount = 0
            recordingDeviceIsAirPods = false
            recordingDevice = AudioDevice(id: "test-iphone", name: "Test-iPhone",
                hasInput: true, transportType: .continuityCaptureWireless)
            testColdAttempt = attempt
            return currentSessionID
        }
    }

    func testConfigurationChanged(running: Bool = false, bufferFormatChanged: Bool = false) {
        recorderQueue.sync {
            testEngineRunning = running
            defer { testEngineRunning = nil }
            handleEngineConfigChange(bufferFormatChanged: bufferFormatChanged)
        }
    }

    func testFailOngoingStartup() {
        recorderQueue.sync { failOngoingRecording(message: "Test-Startabbruch") }
    }

    func testFailWarmStartup() {
        recorderQueue.sync { failStartup("Test-Warmstartfehler") }
    }
}
#endif
