import Foundation
import OSLog

private let polishLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "de.Rehkopf.SPEXT",
    category: "Polish"
)

enum PolishConfiguration {
    static let model = "gpt-6.1-sol"
    static let reasoningEffort = "low"
    static let maxCompletionTokens = 4_096
    static let legacyModelPreferenceKey = "tt_polishModel"

    static func removeLegacyModelPreference(from defaults: UserDefaults) {
        defaults.removeObject(forKey: legacyModelPreferenceKey)
    }
}

/// Takes a raw transcript and has an LLM rewrite it into a
/// ready-to-send, easily readable message.
class PolishService {

    func polish(
        rawText:  String,
        apiKey:   String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            completion(.failure(SPEXTError.invalidURL)); return
        }

        let body = Self.makeRequestBody(rawText: rawText)

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(SPEXTError.encodingFailed)); return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)",  forHTTPHeaderField: "Authorization")
        request.setValue("application/json",  forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = bodyData

        polishLogger.info("Polish request begin model=\(PolishConfiguration.model, privacy: .public) reasoning=\(PolishConfiguration.reasoningEffort, privacy: .public) inputChars=\(rawText.count, privacy: .public)")

        NetworkRetry.dataTask(with: request) { data, response, error in
            if let error = error {
                polishLogger.error("Polish request failed error=\(error.localizedDescription, privacy: .public)")
                completion(.failure(error)); return
            }

            guard let data = data else {
                polishLogger.error("Polish request returned empty response")
                completion(.failure(SPEXTError.emptyResponse)); return
            }

            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                // Quota error is returned as SPEXTError (shared type)
                polishLogger.error("Polish request failed status=\(http.statusCode, privacy: .public)")
                let err = TranscriptionService.parseError(from: data, statusCode: http.statusCode)
                completion(.failure(err)); return
            }

            switch Self.parsePolishedText(from: data) {
            case .success(let trimmed):
                polishLogger.info("Polish request completed outputChars=\(trimmed.count, privacy: .public)")
                completion(.success(FrenchQuoteNormalizer.normalize(trimmed)))
            case .failure(let err):
                polishLogger.error("Polish response decoding failed error=\(err.localizedDescription, privacy: .public)")
                completion(.failure(err))
            }
        }
    }

    static func makeRequestBody(rawText: String) -> [String: Any] {
        [
            "model": PolishConfiguration.model,
            "messages": [
                ["role": "system", "content": PolishPrompt.systemPrompt],
                ["role": "user",   "content": rawText]
            ],
            "reasoning_effort": PolishConfiguration.reasoningEffort,
            // For GPT-6.1 Sol the limit covers both reasoning and visible output tokens.
            "max_completion_tokens": PolishConfiguration.maxCompletionTokens
        ]
    }

    static func parsePolishedText(from data: Data) -> Result<String, SPEXTError> {
        guard
            let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first   = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            return .failure(.decodingFailed)
        }

        if let finishReason = first["finish_reason"] as? String,
           finishReason == "length" {
            return .failure(.polishOutputTruncated)
        }

        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failure(.emptyResponse) }
        return .success(text)
    }

}

enum PolishPrompt {
    static let systemPrompt = """
    Du bist ein persönlicher Schreibassistent. Deine Aufgabe ist es, gesprochene Diktate \
    in sendefertige Nachrichten umzuschreiben – so, als hätte der Nutzer die Nachricht \
    selbst sorgfältig formuliert. \
    \
    Ziel: Optimiere den Text für eine echte Nachricht, die direkt in Mail, Chat oder CRM \
    eingefügt und abgeschickt werden kann. Der Text soll klarer, runder und besser \
    strukturiert sein als das Diktat, aber weiterhin natürlich nach dem Nutzer klingen. \
    \
    WICHTIGSTE REGEL: Erfinde keine neuen Fakten, Zusagen, Termine, Namen, Beträge oder \
    Begründungen. Der Inhalt muss dem entsprechen, was der Nutzer gesagt hat. Du darfst \
    den Text aber sprachlich verdichten, sinnvoll ordnen, Übergänge ergänzen und \
    unvollständige gesprochene Satzfragmente in saubere Sätze verwandeln. \
    \
    Entferne Diktatspuren: Füllwörter, Selbstkorrekturen, Wiederholungen, Versprecher, \
    abgebrochene Satzanfänge und Meta-Anweisungen wie »schreib ihm«, »sag ihr« oder \
    »mach daraus eine Nachricht«, sofern sie nicht selbst Teil der Nachricht sein sollen. \
    \
    Wenn der Nutzer thematisch springt, bringe die Gedanken in eine bessere Reihenfolge: \
    erst Kontext oder Anlass, dann Anliegen, Details, nächste Schritte oder Frage. Kürze \
    ausschweifende Formulierungen, ohne wichtige Inhalte zu verlieren. \
    \
    Ton: locker, sympathisch und professionell. Klar und verbindlich, aber nicht steif. \
    Keine Unternehmensfloskeln, keine übertriebene Höflichkeit, kein Marketing-Sprech. \
    Formuliere lieber aktiv, konkret und menschlich. \
    \
    Was du beibehältst: die Sprache des Eingabetexts, die Anspracheform (Du bleibt Du, \
    Sie bleibt Sie), Anreden und Grußformeln, wenn sie diktiert wurden. Erfinde keine \
    Anrede, keine Grußformel und keinen Betreff, wenn der Nutzer diese nicht gesagt hat. \
    \
    Struktur: Bei kurzen Nachrichten ein kompakter Absatz. Bei mehreren Gedanken kurze \
    Absätze mit jeweils einer Leerzeile dazwischen. Listen nur verwenden, wenn der Nutzer \
    klar mehrere Punkte aufzählt oder die Nachricht dadurch deutlich lesbarer wird. \
    \
    Antworte NUR mit dem fertigen Nachrichtentext – keine Erklärungen, keine \
    umschließenden Anführungszeichen, kein Präfix. Wenn innerhalb der Nachricht \
    Anführungszeichen nötig sind, verwende ausschließlich französische Anführungszeichen \
    nach dem Muster »Text«. Die Spitzen zeigen zum zitierten Wort. Verwende keine deutschen, englischen oder geraden \
    Anführungszeichen.
    """
}
