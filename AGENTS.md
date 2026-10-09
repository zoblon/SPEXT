# SPEXT – Project overview for Codex

macOS menu bar app (Swift/SwiftUI, macOS 14+) for voice input via hotkey.
Recording → OpenAI GPT Transcribe → optional GPT (rewriting) → insertion via paste.

Current app version: **1.0.23** (build **23**).

> **Doc sync rule:** `CLAUDE.md` and `AGENTS.md` must **always have the same content**.
> Every change to one of the two files must also be made in the other (identical wording,
> apart from the title "… for Claude" / "… for Codex"). This applies in particular to the
> version/build number, new architecture or behavior details, and this rule itself. Also keep
> version/build in sync with `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in
> `SPEXT.xcodeproj/project.pbxproj`.

## Project path

```
./SPEXT/
```

## Releases

Release builds are created locally and packaged as ZIP files under `Releases/<version>/`. The folder is excluded from Git via `.gitignore`; the ZIPs are attached as assets to GitHub Releases instead. Each release consists of the app ZIP and a `SHA256.txt` with the checksum (plain file names, verify with `shasum -a 256 -c SHA256.txt`). GitHub adds the source archive for the tag automatically, so no separate source ZIP is uploaded. A loose `.app` is not distributed outside a ZIP, because extra Finder metadata can break its signature check.

## GitHub

The source code is hosted on GitHub (`zoblon/SPEXT`, branch `main`). To publish a new release: bump the version, commit, create the tag `v<version>` (e.g. `v1.0.22`), push, and use `gh release create` to attach the ZIPs and `SHA256.txt`.

## Architecture

```
SPEXTApp.swift          App entry point, MenuBarExtra + Settings scene
Localizable.xcstrings   String catalog (English source, German translation)
InfoPlist.xcstrings     Localized Info.plist texts (microphone usage description)
AppState.swift            Central ObservableObject, coordinates all services
Services/
  AudioRecorder.swift     AVAudioEngine wrapper, PCM segments + level metering + stream monitoring
  RecordingAssembler.swift  Merges segments into M4A after recording, safe across format changes
  HotkeyManager.swift     Global modifier hotkeys via CGEventTap
  TranscriptionService.swift  OpenAI GPT Transcribe API (multipart/form-data upload)
  PolishService.swift     OpenAI Chat Completions (text rewriting)
  PasteService.swift      NSPasteboard + CGEvent Cmd+V simulation
  SystemAudioController.swift  CoreAudio system volume/mute
Models/
  AudioDevice.swift       CoreAudio device management (all devices, Bluetooth)
Views/
  MenuBarView.swift       Popover content when clicking the menu bar icon
  RecordingHUD.swift      Floating pill (dots → waveform) while recording
  SettingsView.swift      Settings (3 tabs: General, Access, Dictionary)
  PermissionSetupView.swift  Permission setup window (first launch / missing permissions)
```

## Recording lifecycle

```
Hotkey KeyDown
  → AppState.startRecording(mode:)
      → HUDWindowController.show()          // pill appears with dots
      → AudioRecorder.startRecording(deviceUID:knownDevice:completion:)
          → start AVAudioEngine cold OR reuse it warm (see below)
          → tap callback: buffer written with a valid format → isMicReady=true → pill shows waveform

Hotkey KeyUp
  → AppState.stopAndTranscribe()
      → AudioRecorder.stopRecording(completion:)   // engine stays warm depending on device
      → TranscriptionService.transcribe(...)
      → [in mode .polish] PolishService.polish(...)
      → PasteService.paste(text + " ")
      → hide HUD
```

## Critical implementation details

### Bluetooth / AirPods (most important special case)
- AirPods in A2DP mode (music) do **not** appear in `inputDevices()` because they have no input streams yet.
- `allAudioDevices()` returns all devices including `hasInput`, `transportType`, `isBluetooth` and `isContinuityLike`.
- `effectiveMicUID` in AppState uses the device cache from `refreshDevices()` and `AudioDevice.preferredMicrophoneUID(...)`: with `tt_preferAirPods = true`, AirPods win; otherwise `selectedMicUID` applies; otherwise the system default. The automatic selection can be turned off in the settings so that an explicitly selected microphone is used even when AirPods are connected. As a result, the hotkey path does not block on CoreAudio scans.
- The device is set via `kAudioOutputUnitProperty_CurrentDevice` on the InputNode's AudioUnit (CoreAudio, not AVAudioSession).
- On `engine.start()`, macOS switches AirPods from A2DP to HFP on its own; this switch takes about 1 second.
- On the first cold start, AirPods Max can briefly report an old 48 kHz client format while the hardware is already switching to 24 kHz HFP. Startup therefore runs as a bounded, cancellable sequence of steps on the recorder queue; configuration notifications can be processed between device check, start and frame timeout. The total budget is 8s with at most three attempts. If attempt 1 delivers no frames, `RecorderStartupPolicy.noWritableFramesTimeout(isAirPods:attempt:)` aborts after 0.75s; later attempts and non-AirPods devices keep 2.0s.
- AirPods `AVAudioEngineConfigurationChange` events are coalesced into a single recovery via `pendingConfigRestartID`. Observer IDs and engine identity cause stale notifications to be ignored. Delayed retries are bound to their recovery ID; at most four recoveries per recording.
- When the system default is used, the actual input device is resolved on the recorder queue, so the correct Bluetooth warm-retention and recovery strategy applies there as well.
- Every cold start uses a new engine generation. Tap and configuration observers are bound to that generation; late callbacks from older generations are ignored. The tap uses `format: nil`; the writer is only created from the PCM buffer format actually delivered and checks sample rate, channels, sample type and interleaving. An unexpected format change triggers recovery.
- If, after the AirPods profile switch, the InputNode still reports its old client format (observed: 48 kHz) while the hardware already runs at 24 kHz, the tap is installed before `engine.start()` with a canonical Float32 format using the current hardware sample rate and channel count. If the formats already match, `format: nil` is kept. This prevents the reproduced `kAudioUnitErr_FormatNotSupported` (`-10868`).
- Segments already written and the overall recording statistics are preserved after a successful recovery. If a recovery happens after speech has been detected, the transcript is afterwards offered for review instead of being pasted automatically.

### iPhone/Continuity startup and error completion
- A configuration notification that is processed late does not tear down an engine that has started in the meantime. Genuine buffer format errors are reported separately and still handled; frame timeout and stream watchdog remain active.
- Configuration changes before the first written buffer go through the bounded startup retry for all devices. After buffers have been written, Continuity also supports the segment-preserving recovery.
- Multiple startup notifications schedule only one retry; delayed retries are bound to retry ID, session and engine generation.
- Internal aborts and warm-start failures complete any pending start completion. On recording errors, AppState also resets the start lock, processing state and hotkey owner, so the next hotkey works without restarting the app.

### Engine warm strategy
- After `stopRecording`: the engine keeps running, the tap stays installed, only `isWriting = false`.
- `warmDeviceUID` remembers which device the engine is warm for.
- On the next `startRecording` with the same UID: `isWriting = true` immediately, no delay.
- Warm retention is device-specific via `AudioRecorder.warmRetentionDuration(for:)`: Bluetooth/AirPods = no warm-up, Continuity/iPhone = 30s, internal/USB mics = 60s.
- `cooldownWorkItem` stops the engine once the respective retention time has elapsed.
- Device change (different UID) → `teardownEngine()` + restart.
- **Bluetooth/AirPods: no warm-up.** The engine is stopped immediately after recording ends (`teardownEngine()`). Reason: a warm engine keeps AirPods in HFP mode; when they automatically fall back to A2DP (to save battery), audible artifacts occur (volume jumps, clicks).

### isMicReady / HUD state
- `isMicReady = false` → HUD shows **DotsLoadingView** (3 pulsing dots).
- `isMicReady = true` → HUD shows **WaveformBarsView** (9 equalizer bars).
- In the cold path, `isMicReady` is not set after `engine.start()` but, for all devices, only after the first buffer has been written with a valid format. Technical readiness is thus separate from the detected speech level.
- After four seconds without a buffer above the speech threshold, the pill shows "No speech signal" (German: "Kein Sprachsignal"). Pauses in speech do not trigger an automatic restart. The notice disappears when the signal returns.
- If a dictation ends with at least four seconds of weak signal after speech has already been detected, the text is offered in the popover with a review notice and not pasted automatically.
- In the warm path: `isMicReady = true` is set immediately in `startRecording`.
- `RealtimeState.micReadySignaled` prevents the tap callback from setting the state more than once. The silence/hallucination guard is unchanged and still decides separately whether a recording may be uploaded.
- `HUDWindowController` creates the NSPanel once and reuses it via `orderFront`/`orderOut`.

### Hotkey system
- `HotkeyManager` uses `CGEventTap` with `.flagsChanged` events.
- Comparison: `HotkeySettings.matches(current:trigger:)`.
- Side-independent triggers compare only `.maskControl`, `.maskAlternate`, `.maskShift`, `.maskCommand`; stored left/right-specific triggers additionally compare the device bits.
- Fn, NumLock and other unknown bits are ignored.
- Defaults: dictation = ROPT+RCMD (rawValue 1572944), message = RCTRL+ROPT (rawValue 794688).
- Stored as `@AppStorage("tt_hotkeyFlags1_v4")` / `tt_hotkeyFlags2_v4`.
- Side-independent defaults that were used briefly (`OPT+CMD`, `CTRL+OPT`) are migrated back to right-side-specific ones on launch.
- Hotkey capture in settings: `FlagCaptureNSView` via `NSEvent.addLocalMonitorForEvents(.flagsChanged)`, accumulates `peakFlags` via `formUnion`, fires `onCapture` once all keys are released.

### Device monitoring
- `AudioObjectAddPropertyListenerBlock` on `kAudioHardwarePropertyDevices` (CoreAudio).
- Fires reliably for Bluetooth devices too (unlike AVCaptureDevice notifications, which do not work for Bluetooth).
- `deviceListenerBlock` is retained as a property; otherwise it would be deallocated.
- If macOS disables the hotkey event tap, it is re-enabled and a key release that happened in the meantime is processed. On teardown, the run loop source and Mach port are invalidated before the callback box is released.
- Parallel device scans carry a generation; only the most recent result may replace the cache.

### Paste
- `PasteService` remembers the target app when recording starts, writes the text to `NSPasteboard.general`, and simulates `⌘V` only if, after 80ms, the same app is still active and the pasteboard is unchanged.
- Text is always pasted with a trailing space (`text + " "`) so typing can continue seamlessly.
- `lastTranscription` in AppState stores the text **without** the space (clean for copying).

### Recording format
- During recording, temporary PCM segments (CAF) are written in the buffer format actually delivered. A format change starts a new segment without deleting earlier ones. File I/O uses its own writer lock; the main thread does not need this lock.
- After recording ends, `RecordingAssembler` merges all segments in order into one M4A file (AAC, 24 kHz, mono, 64 kbps). Conversion runs block by block on the recorder queue, not on the main thread; all temporary segments are deleted afterwards.
- Recording duration is computed from the frames actually written and their respective sample rate. A missing or unreadable segment makes the entire export fail.
- Every 0.5 seconds, a watchdog checks the data stream. At least 2.5 seconds without a buffer cause an error; gaps in between are detected as well. Silent buffers still count as data stream.
- Stopping immediately blocks new recordings until export/transcription has finished. Session IDs prevent late level, readiness and write-error callbacks from affecting a later recording.

### GPT Transcribe integration
- Transcription uses only the fixed model `gpt-transcribe` at the endpoint
  `/v1/audio/transcriptions`; there is no longer a model selection.
- The settings German and English are sent according to the current API contract as
  `languages[]=de` or `languages[]=en`. With automatic detection (`Automatic`), no language hint is
  sent so that detection is not restricted.
- Dictionary entries are sent as separate `keywords[]`. Empty and case-insensitive
  duplicate entries are removed; entries containing `<`, `>`, CR or LF are not sent
  because the API rejects such keywords. The UI logic already blocks new invalid entries.
- For German and English, the model additionally receives a short prompt in the respective
  audio language: verbatim transcription, no invented content, exact names/technical terms and
  natural punctuation. With automatic language detection, the prompt stays empty.
- The response is requested as `json`. `text` is processed; additional
  `languages` metadata may be present and is currently not needed by the UI.
- The request timeout is 120 seconds so that longer dictations also finish reliably.
  The existing single network retry remains active.
- The former UserDefaults key `tt_transcribeModel` is removed on app launch so that
  existing installations are guaranteed to use the single current model.

### GPT rewriting integration
- The "Write message" mode (German: "Nachricht schreiben") uses only the fixed model
  `gpt-6.1-sol` via Chat Completions; there is no longer a model selection.
- Since 1.0.22, GPT-6.1 Sol replaces the previous `gpt-5.6-terra` (GPT-6 has no Terra tier).
  This is based on the controlled comparison of 2026-10-02 (`docs/model-review-gpt6-2026-10-02.md`):
  Sol followed the prompt rules most reliably (no invented salutations, uncertainties
  preserved), costs about the same, but is about 1 second slower than Terra in the median.
  `gpt-6-luna` was rejected because it translated English dictations into German.
- `reasoning_effort` is deliberately set to `low`. This allows efficient ordering,
  grouping and linguistic revision of spoken information without the default `medium`,
  which is unnecessary for this short, latency-sensitive task.
- The current limit `max_completion_tokens = 4096` covers both internal reasoning and
  visible output tokens. `temperature` is not sent (not allowed anyway with GPT-6 when
  reasoning is used); style and factual accuracy
  are defined by `PolishPrompt.systemPrompt`.
- If only the rewriting fails, the original transcript remains in `lastTranscription` for manual copying. Empty rewrites count as errors and do not replace the original.
- The former UserDefaults key `tt_polishModel` is removed on app launch so that
  existing installations are guaranteed to use the single current model.

### Silence/hallucination guard
- Transcription models can output plausible-sounding but invented sentences during
  silence (e.g. "Die OpenAI hat ein Update angekündigt…", "OpenAI has announced an update…") or dictionary words.
- Guard on the audio side (`RecordingQuality.hasMeaningfulSpeech`): a recording is only
  uploaded if the peak level ≥ `minimumPeakAudioLevel` (0.12) **and** the share of
  voiced frames ≥ `minimumVoicedRatio` (5 %). "Voiced" = buffer level ≥
  `speechLevelThreshold` (0.12); the tap callback counts these frames in `RealtimeState.voicedFrames`.
- The peak alone is not enough (noise/clicks can exceed it); hence the additional
  voiced ratio, which filters out isolated spikes.
- If the check fails (key held, but nothing said), the recording is **silently
  discarded** (no upload, **no** error message, `lastError = nil`), exactly like the
  short abort < 1 s. AppState returns to "Ready" (German: "Bereit").
- `gpt-transcribe` does not document a reliable `no_speech_prob` signal, so the
  model-independent audio filter remains the first line of defense.
- In addition, `TranscriptionGuard.isDictionaryOnlyResult` acts as a second line of defense
  for results that consist solely of dictionary words.

### API key security
- The key is stored in the macOS Keychain (`KeychainService`). Old `tt_apiKey` values in UserDefaults are only removed after a successful save and readback; if a Keychain value already exists, the legacy value is cleaned up as well. Save errors keep the previous value and are reported visibly.
- The key is never logged.
- The quota error (`insufficient_quota`) is handled as a separate `SPEXTError.quotaExceeded` and shown prominently in the popover.

### Network calls / retry
- `TranscriptionService` and `PolishService` send their requests via `NetworkRetry.dataTask(...)`
  (defined in `TranscriptionService.swift`) instead of directly via `URLSession.shared`.
- On hotkey KeyDown, `TranscriptionService.prepareConnection(...)` warms up the same `URLSession`
  with a read-only request to `/v1/models/gpt-transcribe`. DNS, TLS and authentication thus
  happen in parallel to the recording instead of after KeyUp. The request is limited to once per 30 seconds;
  errors are only logged technically and do not affect transcription.
- `NetworkRetry` repeats a request **exactly once** (after a 0.8s pause) if the first
  attempt fails with a transient connection error: `NSURLErrorTimedOut`,
  `NetworkConnectionLost`, `CannotConnectToHost`, `CannotFindHost`, `DNSLookupFailed`,
  `SecureConnectionFailed`.
- **No** retry on HTTP errors (4xx/5xx including quota; these arrive as a successful response with
  a status code, not as URL errors) and **no** retry on `notConnectedToInternet` (offline →
  would only delay the error message).
- Safe to retry: the `URLRequest` already holds the body (audio/JSON) in memory; the second
  attempt sends the same bytes without re-reading files. Temp file deletion in
  `TranscriptionService` only runs in the final completion.
- File reading and multipart construction run on a separate queue; API key, language and dictionary are captured immutably before switching queues.

### Performance logging
- `OSLog` measurement points exist for hotkey down, HUD shown, device resolved, mute handled, engine creation, device set, `prepare`, `start`, node/hardware format, frameless start attempt including session/attempt/generation, mic ready buffer, recording stop/file finalized, API request begin/end and paste.
- The HUD `NSPanel` including its SwiftUI content is prepared invisibly right after app launch. The
  hotkey callbacks already run on the main run loop and call the recording lifecycle without an
  additional `DispatchQueue.main.async` hop.
- The connection warm-up is logged with start, HTTP status or technical error code;
  API key and response content are not logged.
- Network retries are logged under the log category `Network` (error code only, no content).
- No API keys and no transcript content are logged; only technical metadata such as model name, language, byte/character count and device class.

## UserDefaults keys

| Key | Type | Meaning |
|-----|-----|-----------|
| `tt_apiKey` | String | Legacy key from UserDefaults; migrated to the Keychain |
| `tt_preferAirPods` | Bool | Prefer AirPods automatically (default: true) |
| `tt_microphoneUID` | String | Microphone UID; fallback when the AirPods automatic selection is active |
| `tt_microphoneName` | String | Display name of the fallback microphone |
| `tt_language` | String | GPT Transcribe language hint ("de", "en", "") |
| `tt_muteOnRecord` | Bool | Mute system audio while recording |
| `tt_polishModel` | String | Legacy key; removed on launch |
| `tt_hotkeyFlags1_v4` | Int | CGEventFlags.rawValue for dictation |
| `tt_hotkeyFlags2_v4` | Int | CGEventFlags.rawValue for message |
| `tt_customWords` | Data | JSON-encoded [String] for GPT Transcribe keywords |
| `tt_transcribeModel` | String | Legacy key; removed on launch |

## Known limitations / open issues

- **First cold start with AirPods**: the HFP delay is unavoidable; the dots remain visible until the first buffer with a valid format has been written; after four seconds without speech level, a notice appears. The warm engine only applies to wired/internal mics (not AirPods, since the codec switch causes music artifacts there).
- **Network retry**: since 1.0.12, transient connection errors (timeout, connection
  lost, host/DNS) are retried automatically **once** (see `NetworkRetry`). With persistent
  problems or HTTP errors, the request still fails (transcription: 120s; rewriting: 30s).
- **Recording length limit:** at most 10 minutes; after that, recording stops automatically and
  is transcribed. With AAC at 64 kbps, the file stays well below the 25 MB API limit.
- **Guillemets in English rewrites (open):** `PolishPrompt` tells the model to use only French quotes (`»Text«`), whatever the dictation language. In message mode, an English dictation can therefore contain `»…«` that the model wrote itself; `FrenchQuoteNormalizer` does not add any, but it also does not undo them. The prompt is intentionally not translated or changed with the interface localization; a language-dependent quote rule would be a separate decision.
- **`engine.isRunning`** is checked in `teardownEngine`, but `AVAudioEngine` can end up in inconsistent internal states if a Bluetooth device is disconnected during recording.
- **Weak AirPods signal:** a continuing, nearly silent data stream can also originate outside the app. The signal warning detects low levels but cannot reliably distinguish pauses in speech, macOS filtering and hardware problems. Hardware acceptance testing with longer spoken texts remains necessary.
- **AirPods unmute**: event-driven via `unmuteOnDeviceChange` + `kAudioHardwarePropertyDevices`. Fires when the HFP profile disappears. 250ms extra buffer afterwards. 3s timeout fallback. Only applies when `muteOnRecord = true`. The 250ms buffer is also cancellable; before a new recording, any pending restoration is completed.

## Localization (English / German)

- Development language is **English**; German is the translation. The app follows the macOS system language (`knownRegions` = en, de; `developmentRegion` = en). Other system languages fall back to English.
- All visible texts live in `SPEXT/Localizable.xcstrings`; the English source text is the key. Info.plist texts (e.g. `NSMicrophoneUsageDescription`) live in `SPEXT/InfoPlist.xcstrings`; the English value is also set in the build settings (`INFOPLIST_KEY_…`).
- SwiftUI texts use literal keys (`Text("Ready")`, `Button("Quit")`, `.help(…)`). Helper views take `LocalizedStringKey` parameters, not `String`, otherwise the text would not be translated. Texts that are not SwiftUI literals (status line, error texts, `SPEXTError`, recorder messages, `window.title`) use `String(localized: "…")`; the status and explanation texts of the popover are collected in `AppStatusText`. Texts with values use interpolation (`%@` in the catalog), never string concatenation.
- Texts stored in properties (e.g. `AppState.statusMessage`) are localized when they are set and compared via the `AppStatusText` constants, never via literals.
- **Not localized:** the prompts sent to OpenAI (`PolishPrompt`, `TranscriptionPromptBuilder`) follow the **dictation language**, not the interface language. Likewise not translated: hotkey labels (`ROPT+RCMD`), model names, log output, test messages.
- `FrenchQuoteNormalizer` turns double quotes into `»…«` (German typography) and depends on the **dictation language**, not on the interface language: only when the setting is German, or with automatic detection when `NLLanguageRecognizer` is clearly confident (≥ 0.9) that the transcript is German. English and unclear text stay unchanged.
- Adding a text: use the English text as key in code, add the entry with its German translation to `Localizable.xcstrings` (Xcode extracts new keys automatically; without Xcode edit the JSON), keep format specifiers identical in both languages.
- `SPEXTTests/run-guard-tests.sh` checks that catalog and code agree (`SPEXTTests/xcstrings_tool.py check`: used keys exist, no stale keys, German translation and format specifiers present) and runs the guard tests twice (interface language German and English) inside a small bundle that carries the real catalog (`-AppleLanguages "(de)"` / `"(en)"`). Text expectations in the tests therefore use `localized(de:en:)`.
- Quick manual check of a language: `open -n SPEXT.app --args -AppleLanguages "(en)"` (or `"(de)"`).

## Permissions (entitlements)

- `com.apple.security.app-sandbox` = false
- `com.apple.security.device.audio-input` = true
- `com.apple.security.network.client` = true (API calls)
- Input Monitoring must be granted manually in System Settings; it is required for global hotkeys (not an entitlement).
- Accessibility must be granted manually in System Settings; it is required for automatic pasting via `⌘V` (not an entitlement).
- On launch, SPEXT checks Input Monitoring, Accessibility and Microphone. If something is missing, a setup window with `Request entries` (German: `Einträge anfordern`) appears.
- macOS TCC does not allow enabling these entries silently; SPEXT can only trigger the system prompts and open the matching settings panes.

## OpenAI model review (check regularly)

- Before every release, and whenever `TranscriptionService`, `PolishService`, the related
  prompts or API parameters are changed or reviewed, check the current official OpenAI
  documentation on models, pricing, deprecations and API contracts live.
- Compare the fixed models `gpt-transcribe` and `gpt-6.1-sol` including
  `reasoning_effort = low` with the currently best-suited alternatives.
  For SPEXT, "best model" means the best demonstrable combination of output quality,
  factual accuracy, completeness, latency, cost and stable API support, not automatically
  the model with the newest number.
- Evaluate transcription candidates using representative German and English recordings:
  word accuracy, proper names/dictionary, punctuation, silence/hallucination behavior,
  supported language and keyword parameters, latency and cost.
- Evaluate rewriting candidates using representative real dictations: preservation of all facts,
  sensible ordering and grouping, natural language, tone, unwanted additions, latency,
  cost and appropriate reasoning effort.
- Do not adopt new models automatically just because they have been released. Proactively
  suggest interesting candidates to the maintainer with pros and cons; only switch after
  the maintainer's decision and a controlled comparison with the previous model.

## Reference project (check regularly)

- **blitztext-app** (open-source app by the YouTuber the SPEXT idea came from):
  https://github.com/cmagnussen/blitztext-app
- Same basic idea (macOS menu bar, hotkey → Whisper → optional GPT → paste), Swift/SwiftUI.
- State of analysis (2026-10-02): `main` unchanged since 2026-06-02 (three commits, no release,
  no PR merged). blitztext still uses `whisper-1` (shutdown 2027-02-26) as well as
  `gpt-4o-mini`/`gpt-4o`. SPEXT's audio handling (AVAudioEngine, warm engine, AirPods/HFP),
  GPT Transcribe model and network retry are considerably more mature.
- Only open, unreviewed community PRs and forks are of interest (as of 2026-10-02):
  #15 pause media playback instead of muting, #8 start/stop sounds, #18 input-only
  recording via Audio Queue against `-10877` with differing input/output formats,
  fork `mschnitzler-creator/blitztext-app-v2` with a local dictation history. None of this has
  been adopted; the decision lies with the maintainer.
- Additional blitztext features are **offline transcription via WhisperKit/CoreML** as well as
  separate modes for calmer messages and emojis. Deliberately not adopted because that
  performance pass was not meant to introduce new features.
- **Check during future reviews** (and proactively suggest to the maintainer):
  1. **Stability/performance:** new approaches such as a more mature WhisperKit integration, retry,
     streaming paste, a faster pipeline.
  2. **New features:** even though SPEXT deliberately stays lean, if blitztext gets interesting
     features (e.g. new modes, local models, UX ideas), briefly present them to the maintainer,
     who decides case by case whether to adopt anything.

## Language

Code identifiers and comments are in **English**. The UI is localized in **English** (development
language) and **German** (see "Localization").
