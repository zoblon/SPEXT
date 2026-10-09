import Foundation
import CoreGraphics
import AVFoundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct TranscriptionGuardTests {
    static func main() {
        testIPhoneStartupLifecycle()
        testRecordingReliability()

        let words = ["Claude-Datei", "Claude-MD", "Mirco", "Neusta", "Sideklick", "Wenite"]

        expect(
            TranscriptionConfiguration.model == "gpt-transcribe",
            "GPT Transcribe muss das einzige fest konfigurierte Transkriptionsmodell sein"
        )
        expect(
            TranscriptionConfiguration.requestTimeout == 120,
            "Längere Diktate brauchen ausreichend Zeit für Upload und Transkription"
        )
        expect(
            TranscriptionConfiguration.connectionWarmupInterval == 30,
            "Verbindungs-Warmup darf bei schnell aufeinanderfolgenden Aufnahmen nicht mehrfach feuern"
        )
        let warmupRequest = TranscriptionService.makeConnectionWarmupRequest(apiKey: "test-key")
        expect(
            warmupRequest?.url?.absoluteString
                == "https://api.openai.com/v1/models/gpt-transcribe"
                && warmupRequest?.httpMethod == "GET"
                && warmupRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer test-key",
            "Verbindungs-Warmup muss den dokumentierten read-only Modellabruf verwenden"
        )
        let migrationDomain = "de.Rehkopf.SPEXT.Tests.TranscriptionMigration"
        let migrationDefaults = UserDefaults(suiteName: migrationDomain)!
        migrationDefaults.set(
            "legacy-selection",
            forKey: TranscriptionConfiguration.legacyModelPreferenceKey
        )
        TranscriptionConfiguration.removeLegacyModelPreference(from: migrationDefaults)
        expect(
            migrationDefaults.object(forKey: TranscriptionConfiguration.legacyModelPreferenceKey) == nil,
            "Gespeicherte Legacy-Modellauswahlen müssen beim Start entfernt werden"
        )
        migrationDefaults.removePersistentDomain(forName: migrationDomain)

        expect(
            PolishConfiguration.model == "gpt-6.1-sol",
            "Umformulierung muss fest auf GPT-6.1 Sol konfiguriert sein"
        )
        expect(
            PolishConfiguration.reasoningEffort == "low",
            "Umformulierung soll Informationen mit effizientem Low-Reasoning ordnen"
        )
        let polishBody = PolishService.makeRequestBody(rawText: "Zuerst Punkt zwei, danach Punkt eins.")
        expect(
            polishBody["model"] as? String == "gpt-6.1-sol"
                && polishBody["reasoning_effort"] as? String == "low"
                && polishBody["max_completion_tokens"] as? Int
                    == PolishConfiguration.maxCompletionTokens
                && polishBody["max_tokens"] == nil
                && polishBody["temperature"] == nil,
            "Sol-Request muss die aktuellen Reasoning- und Token-Parameter verwenden"
        )
        let polishMessages = polishBody["messages"] as? [[String: String]]
        expect(
            polishMessages?.first?["content"] == PolishPrompt.systemPrompt
                && polishMessages?.last?["content"] == "Zuerst Punkt zwei, danach Punkt eins.",
            "Umformulierungs-Request muss Prompt und Rohtext unverändert übertragen"
        )
        let polishMigrationDomain = "de.Rehkopf.SPEXT.Tests.PolishMigration"
        let polishMigrationDefaults = UserDefaults(suiteName: polishMigrationDomain)!
        polishMigrationDefaults.set(
            "gpt-4o",
            forKey: PolishConfiguration.legacyModelPreferenceKey
        )
        PolishConfiguration.removeLegacyModelPreference(from: polishMigrationDefaults)
        expect(
            polishMigrationDefaults.object(
                forKey: PolishConfiguration.legacyModelPreferenceKey
            ) == nil,
            "Gespeicherte Umformulierungsmodelle müssen beim Start entfernt werden"
        )
        polishMigrationDefaults.removePersistentDomain(forName: polishMigrationDomain)

        expect(
            TranscriptionConfiguration.languageHints(for: "de") == ["de"]
                && TranscriptionConfiguration.languageHints(for: "en") == ["en"],
            "Explizite Spracheinstellungen müssen als languages[]-Hinweise übertragen werden"
        )
        expect(
            TranscriptionConfiguration.languageHints(for: "").isEmpty,
            "Automatische Spracherkennung darf nicht durch einen Sprachhinweis eingeschränkt werden"
        )

        let keywords = TranscriptionConfiguration.keywords(
            from: [" Neusta ", "neusta", "SPEXT", "mehr\nzeilig", "<ungültig>"]
        )
        expect(
            keywords == ["Neusta", "SPEXT"],
            "Keywords müssen getrimmt, dedupliziert und API-sicher gefiltert werden"
        )

        let germanPrompt = TranscriptionPromptBuilder.prompt(forLanguage: "de")
        expect(
            germanPrompt.contains("ausschließlich tatsächlich gesprochene Wörter")
                && germanPrompt.contains("deutsche Zeichensetzung"),
            "Deutscher Prompt muss wörtliche Transkription ohne erfundene Inhalte anfordern"
        )
        let englishPrompt = TranscriptionPromptBuilder.prompt(forLanguage: "en")
        expect(
            englishPrompt.contains("only words that were actually spoken")
                && englishPrompt.contains("English punctuation"),
            "Englischer Prompt muss zur Audiosprache passen"
        )
        expect(
            TranscriptionPromptBuilder.prompt(forLanguage: "").isEmpty,
            "Bei Auto-Erkennung darf kein möglicherweise fremdsprachiger Prompt gesendet werden"
        )

        let multipartBoundary = "SPEXT-Test"
        let multipartBody = TranscriptionService.buildBody(
            boundary: multipartBoundary,
            audioData: Data([0x01, 0x02]),
            filename: "audio.m4a",
            mimeType: "audio/m4a",
            languageHints: ["de"],
            keywords: ["Neusta", "SPEXT"],
            prompt: germanPrompt
        )
        let multipart = String(decoding: multipartBody, as: UTF8.self)
        expect(
            multipart.contains("name=\"model\"\r\n\r\ngpt-transcribe\r\n"),
            "Multipart-Request muss ausschließlich GPT Transcribe anfordern"
        )
        expect(
            multipart.contains("name=\"languages[]\"\r\n\r\nde\r\n")
                && !multipart.contains("name=\"language\"\r\n"),
            "Multipart-Request muss den neuen pluralen Sprachparameter verwenden"
        )
        expect(
            multipart.contains("name=\"keywords[]\"\r\n\r\nNeusta\r\n")
                && multipart.contains("name=\"keywords[]\"\r\n\r\nSPEXT\r\n"),
            "Alle Wörterbuchbegriffe müssen als separate keywords[] gesendet werden"
        )
        expect(
            multipart.contains("name=\"prompt\"\r\n\r\n\(germanPrompt)\r\n"),
            "Sprachpassender Diktatkontext muss an GPT Transcribe gesendet werden"
        )
        expect(
            multipart.contains("name=\"response_format\"\r\n\r\njson\r\n")
                && multipart.hasSuffix("--\(multipartBoundary)--\r\n"),
            "Multipart-Request muss eine vollständige JSON-Antwort anfordern"
        )

        let transcriptionResponse = """
        {
          "text": "Hallo SPEXT.",
          "languages": [{ "code": "de" }]
        }
        """.data(using: .utf8)!
        expect(
            TranscriptionService.parseTranscriptionText(from: transcriptionResponse) == "Hallo SPEXT.",
            "GPT-Transcribe-Antworten mit Sprachmetadaten müssen weiterhin korrekt gelesen werden"
        )

        expect(
            TranscriptionGuard.isDictionaryOnlyResult(
                "Claude-Datei, Claude-MD, Mirco, Neusta, Sideklick und Wenite",
                customWords: words
            ),
            "Reine Wörterbuch-Ausgabe muss erkannt werden"
        )

        expect(
            !TranscriptionGuard.isDictionaryOnlyResult(
                "Ich habe hier die Claude-Datei und danach sprechen wir über Sideklick.",
                customWords: words
            ),
            "Normales Diktat mit Wörterbuch-Begriffen darf nicht blockiert werden"
        )

        expect(
            !TranscriptionGuard.isDictionaryOnlyResult(
                "Claude-Datei, Claude-MD, Mirco",
                customWords: []
            ),
            "Ohne Wörterbuch darf nichts als Wörterbuch-Halluzination gelten"
        )

        expect(
            !RecordingQuality.hasMeaningfulSpeech(peakAudioLevel: 0, voicedFrames: 0, totalFrames: 48_000),
            "Digitale Stille darf nicht als Sprache gelten"
        )

        expect(
            !RecordingQuality.hasMeaningfulSpeech(peakAudioLevel: 0.05, voicedFrames: 0, totalFrames: 48_000),
            "Leises Dauerrauschen (Pegel unter Sprach-Schwelle) darf nicht an die API gehen"
        )

        expect(
            !RecordingQuality.hasMeaningfulSpeech(peakAudioLevel: 0.6, voicedFrames: 600, totalFrames: 48_000),
            "Ein einzelner kurzer Knackser (Spitze hoch, aber kaum gesprochene Frames) darf nicht durchrutschen"
        )

        expect(
            RecordingQuality.hasMeaningfulSpeech(peakAudioLevel: 0.6, voicedFrames: 12_000, totalFrames: 48_000),
            "Echtes Sprachsignal mit ausreichendem gesprochenem Anteil darf nicht blockiert werden"
        )

        expect(
            RecordingLimits.maximumDuration == 10 * 60,
            "Die maximale Aufnahmedauer muss 10 Minuten betragen"
        )

        expect(
            CustomWordList.adding("  Mirco  ", to: ["Claude"]) == ["Claude", "Mirco"],
            "Wörterbuch-Begriffe müssen getrimmt hinzugefügt werden"
        )

        expect(
            CustomWordList.adding("mirco", to: ["Mirco"]) == ["Mirco"],
            "Wörterbuch-Begriffe dürfen case-insensitiv nicht doppelt hinzugefügt werden"
        )

        expect(
            CustomWordList.adding("mehr\nzeilig", to: ["Mirco"]) == ["Mirco"],
            "Wörterbuch-Begriffe mit API-inkompatiblen Zeilenumbrüchen müssen abgelehnt werden"
        )

        expect(
            CustomWordList.adding("<Neusta>", to: ["Mirco"]) == ["Mirco"],
            "Wörterbuch-Begriffe mit API-inkompatiblen spitzen Klammern müssen abgelehnt werden"
        )

        expect(
            CustomWordList.replacing(original: "Mirco", with: " mirco ", in: ["Mirco", "Claude"]) == ["Mirco", "Claude"],
            "Wörterbuch-Bearbeitung darf keine case-insensitiven Duplikate erzeugen"
        )

        expect(
            CustomWordList.replacing(original: "Mirco", with: "Neusta", in: ["Mirco", "Claude"]) == ["Neusta", "Claude"],
            "Wörterbuch-Bearbeitung muss bestehende Einträge ersetzen"
        )

        expect(
            AppStatusText.pasteBlocked.count <= 24,
            "Status für blockiertes Einfügen muss kurz genug für das Menü sein"
        )

        expect(
            AppStatusText.pasteBlockedExplanation.contains("Bedienungshilfen")
                && AppStatusText.pasteBlockedExplanation.contains("Eingabeüberwachung")
                && AppStatusText.pasteBlockedExplanation.contains("⌘V"),
            "Fehlertext muss Ursache, falschen Berechtigungsbereich und manuellen Fallback nennen"
        )

        expect(
            AppStatusText.hotkeysBlocked.count <= 24,
            "Status für blockierte Hotkeys muss kurz genug für das Menü sein"
        )

        expect(
            AppStatusText.hotkeysBlockedExplanation.contains("Eingabeüberwachung")
                && AppStatusText.hotkeysBlockedExplanation.contains("Bedienungshilfen"),
            "Hotkey-Fehlertext muss Eingabeüberwachung von Bedienungshilfen abgrenzen"
        )

        expect(
            HotkeySettings.defaultDirectRaw == 1_572_944,
            "Diktat-Default muss wieder rechts-spezifisch ROPT+RCMD sein"
        )

        expect(
            HotkeySettings.defaultPolishRaw == 794_688,
            "Nachricht-Default muss wieder rechts-spezifisch RCTRL+ROPT sein"
        )

        expect(
            HotkeySettings.normalizedStoredRaw(1_572_864) == HotkeySettings.defaultDirectRaw,
            "Seitenunabhängiger Diktat-Default muss automatisch auf rechts-spezifisch migriert werden"
        )

        expect(
            HotkeySettings.normalizedStoredRaw(786_432) == HotkeySettings.defaultPolishRaw,
            "Seitenunabhängiger Nachricht-Default muss automatisch auf rechts-spezifisch migriert werden"
        )

        expect(
            !HotkeySettings.matches(
                current: CGEventFlags(rawValue: CGEventFlags([.maskAlternate, .maskCommand]).rawValue | 0x00000020 | 0x00000008),
                trigger: CGEventFlags(rawValue: UInt64(HotkeySettings.defaultDirectRaw))
            ),
            "Rechts-spezifischer Diktat-Hotkey darf linke Modifier nicht akzeptieren"
        )

        expect(
            HotkeySettings.matches(
                current: CGEventFlags(rawValue: CGEventFlags([.maskAlternate, .maskCommand]).rawValue | 0x00000040 | 0x00000010),
                trigger: CGEventFlags(rawValue: UInt64(HotkeySettings.defaultDirectRaw))
            ),
            "Rechts-spezifischer Diktat-Hotkey muss rechte Modifier akzeptieren"
        )

        let checklist = PermissionChecklist(
            hasInputMonitoring: false,
            hasAccessibility: true,
            hasMicrophone: false
        )
        expect(checklist.needsSetup, "Fehlende Berechtigungen müssen ein Setup-Angebot auslösen")
        expect(
            checklist.missingPermissions.map(\.title) == ["Eingabeüberwachung", "Mikrofon"],
            "Berechtigungscheck muss fehlende Rechte in nutzerverständlicher Reihenfolge melden"
        )

        let normalizedQuotes = FrenchQuoteNormalizer.normalize(
            #"Er sagte "Hallo" und dann „bis später“."#
        )
        expect(
            normalizedQuotes == "Er sagte »Hallo« und dann »bis später«.",
            "Doppelte Anführungszeichen müssen zu nach innen zeigenden Guillemets normalisiert werden"
        )

        expect(
            PolishPrompt.systemPrompt.contains("»schreib ihm«")
                && PolishPrompt.systemPrompt.contains("französische Anführungszeichen")
                && PolishPrompt.systemPrompt.contains("»Text«")
                && !PolishPrompt.systemPrompt.contains(#""schreib ihm""#),
            "Umformulierungs-Prompt muss ausschließlich nach innen zeigende französische Beispiel-Anführungszeichen verwenden"
        )

        let completePolishResponse = """
        {
          "choices": [
            {
              "finish_reason": "stop",
              "message": { "content": " Fertiger Text. " }
            }
          ]
        }
        """.data(using: .utf8)!
        switch PolishService.parsePolishedText(from: completePolishResponse) {
        case .success(let text):
            expect(text == "Fertiger Text.", "Vollständige Umformulierungsantwort muss getrimmt werden")
        case .failure:
            expect(false, "Vollständige Umformulierungsantwort darf keinen Fehler liefern")
        }

        let truncatedPolishResponse = """
        {
          "choices": [
            {
              "finish_reason": "length",
              "message": { "content": "Unvollständiger Text" }
            }
          ]
        }
        """.data(using: .utf8)!
        switch PolishService.parsePolishedText(from: truncatedPolishResponse) {
        case .success:
            expect(false, "Abgeschnittene Umformulierungsantwort darf nicht eingefügt werden")
        case .failure(let error):
            expect(
                error.errorDescription?.contains("abgeschnitten") == true,
                "Abgeschnittene Umformulierungsantwort muss einen verständlichen Fehler liefern"
            )
        }

        let builtInMic = AudioDevice(
            id: "builtin",
            name: "MacBook Pro Mikrofon",
            hasInput: true,
            transportType: .builtIn
        )
        let continuityMic = AudioDevice(
            id: "iphone",
            name: "Annas iPhone Mikrofon",
            hasInput: true,
            transportType: .continuityCaptureWireless
        )
        let airPodsOutputOnly = AudioDevice(
            id: "airpods",
            name: "Annas AirPods Pro",
            hasInput: false,
            transportType: .bluetooth
        )

        expect(
            AudioDevice.preferredMicrophoneUID(
                from: [builtInMic, continuityMic, airPodsOutputOnly],
                selectedMicUID: continuityMic.id
            ) == airPodsOutputOnly.id,
            "Verbundene AirPods müssen automatisch vor dem Fallback-Mikrofon verwendet werden"
        )

        expect(
            AudioDevice.preferredMicrophoneUID(
                from: [builtInMic, continuityMic],
                selectedMicUID: continuityMic.id
            ) == continuityMic.id,
            "Ohne AirPods muss das gewählte iPhone-Mikrofon als Fallback verwendet werden"
        )

        expect(
            AudioDevice.preferredMicrophoneUID(
                from: [builtInMic],
                selectedMicUID: ""
            ) == nil,
            "Ohne AirPods und ohne Fallback soll das System-Standardmikrofon verwendet werden"
        )

        expect(
            AudioRecorder.warmRetentionDuration(for: airPodsOutputOnly) == nil,
            "Bluetooth-Mikrofone dürfen nicht warm gehalten werden"
        )

        expect(
            AudioRecorder.warmRetentionDuration(for: continuityMic) == 30,
            "Continuity-/iPhone-Mikrofone sollen 30 Sekunden warm bleiben"
        )

        expect(
            AudioRecorder.warmRetentionDuration(for: builtInMic) == 60,
            "Interne und USB-Mikrofone sollen 60 Sekunden warm bleiben"
        )

        expect(
            RecorderStartupPolicy.noWritableFramesTimeout(isAirPods: true, attempt: 1) == 0.75,
            "AirPods sollen den ersten startenden, aber frame-losen Versuch schnell abbrechen"
        )

        expect(
            RecorderStartupPolicy.noWritableFramesTimeout(isAirPods: true, attempt: 2) == 2.0,
            "Spätere AirPods-Versuche brauchen den konservativen Frame-Timeout"
        )

        expect(
            RecorderStartupPolicy.noWritableFramesTimeout(isAirPods: false, attempt: 1) == 2.0,
            "Nicht-AirPods behalten den konservativen Frame-Timeout"
        )

        expect(
            !MicReadinessPolicy.shouldSignalMicReady(wroteFormatValidBuffer: false),
            "Ohne gültig geschriebenen Buffer darf das Mikrofon nicht bereit melden"
        )

        expect(
            MicReadinessPolicy.shouldSignalMicReady(wroteFormatValidBuffer: true),
            "Auch ein stiller, formatgültig geschriebener AirPods-Buffer muss technische Bereitschaft melden"
        )
        print("PASS: Alle SPEXT-Regressionsprüfungen")
    }
}

private func testIPhoneStartupLifecycle() {
    // Runs the real recorder handlers; only engine.start is replaced.
    func pump(_ seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.main.run(until: min(deadline, Date().addingTimeInterval(0.01)))
        }
    }
    let recorder = AudioRecorder()
    var completions: [RecordingStartResult] = []
    var attempts: [Int] = []
    let first = recorder.testBeginStartup(completion: { completions.append($0) },
        attempt: { number in DispatchQueue.main.async { attempts.append(number) } })
    recorder.testConfigurationChanged(running: true)
    recorder.testConfigurationChanged(running: true)
    pump(0.4)
    expect(attempts.isEmpty && completions.isEmpty,
           "Eine verzögerte Notification darf die bereits laufende iPhone-Engine nicht neu starten")
    recorder.testConfigurationChanged()
    recorder.testConfigurationChanged()
    pump(0.45)
    expect(attempts == [2], "iPhone-Konfigurationswechsel muss genau einen erneuten Start auslösen")
    expect(completions.isEmpty, "iPhone-Konfigurationswechsel darf den offenen Start nicht abbrechen")
    recorder.testFailOngoingStartup()
    recorder.testFailOngoingStartup()
    pump(0.05)
    expect(completions.count == 1 && completions[0].sessionID == first && !completions[0].succeeded,
           "Interner Startabbruch muss genau eine Fehler-Completion liefern und die Startsperre lösen")

    // The same recorder must be able to record again without an app restart.
    let second = recorder.testBeginStartup(completion: { completions.append($0) },
        attempt: { number in DispatchQueue.main.async { attempts.append(number) } })
    recorder.testConfigurationChanged()
    var stopResult: RecordingResult?
    recorder.stopRecording { result in DispatchQueue.main.async { stopResult = result } }
    pump(0.08)
    expect(stopResult?.sessionID == second && completions.count == 2,
           "Loslassen während des iPhone-Starts muss Start und Stop abschließen")
    let third = recorder.testBeginStartup(completion: { completions.append($0) },
        attempt: { number in DispatchQueue.main.async { attempts.append(number) } })
    pump(0.4)
    expect(attempts == [2], "Ein alter verzögerter Retry darf die neue Sitzung nicht starten")
    recorder.testConfigurationChanged(running: true, bufferFormatChanged: true)
    pump(0.4)
    expect(attempts == [2, 2], "Ein echter Buffer-Formatfehler muss auch bei laufender Engine behandelt werden")
    recorder.testFailWarmStartup()
    pump(0.05)
    expect(completions.count == 3 && completions.last?.sessionID == third && completions.last?.succeeded == false,
           "Auch ein Warmstartfehler muss die Start-Completion abschließen")
    print("PASS: iPhone-Start, zusammengefasste Konfigurationswechsel, Fehlerabschluss, Stop und erneuter Start")
}

private func testRecordingReliability() {
    expect(
        RecorderStartupPolicy.action(attempt: 1, elapsed: 0.2, event: .formatChanged) == .retry
            && RecorderStartupPolicy.action(attempt: 2, elapsed: 0.8, event: .writableFrames) == .succeed,
        "Ein 48→24-kHz-Wechsel während des Starts muss genau in einen erfolgreichen Wiederanlauf führen"
    )
    expect(
        RecorderStartupPolicy.action(attempt: 1, elapsed: 0.1, event: .formatUnsupported) == .retry,
        "-10868 muss nach erneuter Format-/Geräteauflösung einen begrenzten Wiederanlauf erlauben"
    )
    expect(
        RecorderStartupPolicy.action(attempt: 3, elapsed: 2, event: .formatUnsupported) == .fail
            && RecorderStartupPolicy.action(attempt: 2, elapsed: 8.1, event: .noFrames) == .fail,
        "Anhaltend ungültige Formate oder fehlende Frames müssen begrenzt enden"
    )
    expect(
        RecorderStartupPolicy.action(attempt: 1, elapsed: 0.1, event: .stopped) == .cancel,
        "Stop während jeder Startphase muss weitere Versuche abbrechen"
    )
    expect(
        RecordingOwnershipPolicy.mayStop(owner: .direct, trigger: .direct)
            && !RecordingOwnershipPolicy.mayStop(owner: .direct, trigger: .polish)
            && RecordingOwnershipPolicy.mayStop(owner: .polish, trigger: nil),
        "Nur der besitzende Hotkey oder der Aufnahme-Timer darf die Aufnahme stoppen"
    )
    expect(
        GenerationPolicy.shouldApply(completed: 4, latest: 4)
            && !GenerationPolicy.shouldApply(completed: 3, latest: 4),
        "Alte Engine-/Gerätescan-Ergebnisse dürfen eine neuere Generation nicht überschreiben"
    )
    expect(
        KeychainMigrationPolicy.shouldRemoveLegacy(
            existingKey: "vorhanden",
            attemptedKey: "alt",
            saveSucceeded: false,
            readbackKey: "vorhanden"
        )
            && KeychainMigrationPolicy.shouldRemoveLegacy(
                existingKey: "",
                attemptedKey: "alt",
                saveSucceeded: true,
                readbackKey: "alt"
            )
            && !KeychainMigrationPolicy.shouldRemoveLegacy(
                existingKey: "",
                attemptedKey: "alt",
                saveSucceeded: false,
                readbackKey: ""
            ),
        "Legacy-Key darf nur bei vorhandenem oder per Readback bestätigtem Schlüsselbundwert gelöscht werden"
    )

    let emptyPolish = Data(#"{"choices":[{"message":{"content":"   "},"finish_reason":"stop"}]}"#.utf8)
    if case .success = PolishService.parsePolishedText(from: emptyPolish) {
        expect(false, "Eine leere Umformulierung darf das Originaldiktat nicht ersetzen")
    }
    let airPods = AudioDevice(id: "airpods", name: "AirPods Max", hasInput: true, transportType: .bluetooth)
    let internalMic = AudioDevice(id: "internal", name: "Mac-Mikrofon", hasInput: true, transportType: .builtIn)
    expect(AudioDevice.preferredMicrophoneUID(from: [airPods, internalMic], selectedMicUID: "internal", preferAirPods: false) == "internal",
           "Eine explizite Mikrofonwahl muss bei abgeschalteter AirPods-Automatik gelten")
    expect(AudioDevice.preferredMicrophoneUID(from: [airPods], selectedMicUID: "", preferAirPods: false) == nil,
           "Systemstandard muss ohne AirPods-Automatik an macOS delegiert werden")
    expect(!RecordingHealthPolicy.hasStalled(now: 100.2, lastBufferAt: 100), "Frische stille Buffer sind kein Verbindungsabbruch")
    expect(RecordingHealthPolicy.hasStalled(now: 103, lastBufferAt: 100), "Fehlende Buffer müssen als Ausfall erkannt werden")
    expect(RecordingHealthPolicy.needsSignalWarning(now: 105, lastSpeechAt: 100), "Lange schwache Signalphasen brauchen einen Hinweis")
    expect(!RecordingHealthPolicy.needsSignalWarning(now: 105, lastSpeechAt: 104), "Erneute Sprache muss den Hinweis zurücknehmen")
    expect(MicReadinessPolicy.shouldSignalMicReady(wroteFormatValidBuffer: true),
           "Technische Bereitschaft darf nicht länger von der Sprachschwelle abhängen")
    expect(!RecordingQuality.hasMeaningfulSpeech(peakAudioLevel: 0.013848, voicedFrames: 0, totalFrames: 24_000),
           "Ein technisch bereiter, aber schwacher AirPods-Stream darf weiterhin nicht hochgeladen werden")

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SPEXT-AudioTests-" + UUID().uuidString)
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // Different frequencies make the order and preservation of both segments measurable.
        let first = try makeAudioFixture(directory: directory, rate: 48_000, channels: 2, seconds: 2, frequency: 300)
        let second = try makeAudioFixture(directory: directory, rate: 24_000, channels: 1, seconds: 3, frequency: 700)
        let third = try makeAudioFixture(directory: directory, rate: 44_100, channels: 1, seconds: 1, frequency: 1000)
        let url = try RecordingAssembler.export(segments: [first, second, third])
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try AVAudioFile(forReading: url)
        let duration = Double(file.length) / file.processingFormat.sampleRate
        expect(abs(duration - 6) < 0.1, "Nach Formatwechseln müssen alle sechs Sekunden erhalten bleiben")
        expect(file.processingFormat.sampleRate == 24_000 && file.processingFormat.channelCount == 1,
               "Zusammengeführte Aufnahme muss ein einheitliches Format haben")
        for (position, frequency) in [(0.5, 300.0), (3.0, 700.0), (5.3, 1000.0)] {
            file.framePosition = AVAudioFramePosition(position * file.processingFormat.sampleRate)
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4800)!
            try file.read(into: buffer)
            let samples = buffer.floatChannelData![0]
            var crossings = 0
            var energy: Float = 0
            for index in 1..<Int(buffer.frameLength) {
                if samples[index - 1] < 0 && samples[index] >= 0 { crossings += 1 }
                energy += samples[index] * samples[index]
            }
            let observed = Double(crossings) / (Double(buffer.frameLength) / file.processingFormat.sampleRate)
            expect(abs(observed - frequency) < 15, "Abschnitt bei \(position)s muss in richtiger Reihenfolge und Tonhöhe erhalten bleiben")
            expect(energy / Float(buffer.frameLength) > 0.01, "Abschnitte dürfen nicht zu Stille werden")
        }
        do {
            _ = try RecordingAssembler.export(segments: [first, directory.appendingPathComponent("fehlt.caf")])
            expect(false, "Ein fehlender Abschnitt darf keine erfolgreiche Teilaufnahme ergeben")
        } catch { }
        do {
            _ = try RecordingAssembler.export(segments: [])
            expect(false, "Eine leere Aufnahme darf nicht erfolgreich exportiert werden")
        } catch { }
        // Maximum dictation length: block-wise conversion must not truncate any data.
        let long = try makeAudioFixture(directory: directory, rate: 24_000, channels: 1, seconds: 600, frequency: 440)
        let started = Date()
        let longURL = try RecordingAssembler.export(segments: [long])
        defer { try? FileManager.default.removeItem(at: longURL) }
        let longFile = try AVAudioFile(forReading: longURL)
        expect(abs(Double(longFile.length) / longFile.processingFormat.sampleRate - 600) < 0.1,
               "Ein Zehn-Minuten-Diktat muss vollständig exportiert werden")
        let size = try FileManager.default.attributesOfItem(atPath: longURL.path)[.size] as! NSNumber
        expect(size.intValue < 25_000_000, "Auch das längste Diktat muss unter dem Upload-Limit bleiben")
        print("PASS: Audio-Zusammenführung, Formatwechsel, Reihenfolge, Fehlerpfade, 10-Minuten-Export (\(String(format: "%.2f", Date().timeIntervalSince(started)))s)")
    } catch {
        expect(false, "Audio-Integrationstest fehlgeschlagen: \(error)")
    }
}

private func makeAudioFixture(directory: URL, rate: Double, channels: AVAudioChannelCount,
                              seconds: Double, frequency: Double) throws -> URL {
    let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
    let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)!
    var settings = format.settings
    settings[AVLinearPCMIsNonInterleaved] = false
    let file = try AVAudioFile(forWriting: url, settings: settings)
    var position = 0
    let total = Int(rate * seconds)
    while position < total {
        let count = min(4096, total - position)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
        buffer.frameLength = AVAudioFrameCount(count)
        for channel in 0..<Int(channels) {
            for index in 0..<count {
                buffer.floatChannelData![channel][index] = Float(sin(2 * .pi * frequency * Double(position + index) / rate)) * 0.25
            }
        }
        try file.write(from: buffer)
        position += count
    }
    return url
}
