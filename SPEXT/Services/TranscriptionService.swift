import Foundation
import OSLog

private let transcriptionLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "de.Rehkopf.SPEXT",
    category: "Transcription"
)

private let networkLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "de.Rehkopf.SPEXT",
    category: "Network"
)

// MARK: - Network Retry

/// Runs a URLSession data task and retries it **exactly once** if
/// the first attempt fails with a transient connection error
/// (timeout, connection lost, host/DNS unreachable).
///
/// Does **not** retry on HTTP errors (4xx/5xx incl. quota) – these arrive as a
/// successful response with a status code, not as a URL error – nor
/// for a request that already succeeded. The original `URLRequest` already holds
/// the complete body (e.g. the audio data) in memory; a retry therefore sends
/// exactly the same bytes again without having to re-read files.
enum NetworkRetry {

    /// Short pause before the second attempt so a brief Wi-Fi dropout can recover.
    static let retryDelay: TimeInterval = 0.8

    static func dataTask(
        with request: URLRequest,
        session: URLSession = .shared,
        completion: @escaping (Data?, URLResponse?, Error?) -> Void
    ) {
        session.dataTask(with: request) { data, response, error in
            if let error, isTransient(error) {
                networkLogger.info(
                    "Transient network error – retrying once code=\((error as NSError).code, privacy: .public)"
                )
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + retryDelay) {
                    session.dataTask(with: request) { retryData, retryResponse, retryError in
                        if let retryError, isTransient(retryError) {
                            networkLogger.error(
                                "Retry failed code=\((retryError as NSError).code, privacy: .public)"
                            )
                        }
                        completion(retryData, retryResponse, retryError)
                    }.resume()
                }
                return
            }
            completion(data, response, error)
        }.resume()
    }

    /// Only real, temporary connection errors count as retryable.
    /// Intentionally NOT included: `notConnectedToInternet` (offline – a retry would only
    /// delay the error message) as well as all HTTP/API errors.
    static func isTransient(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        switch nsError.code {
        case NSURLErrorTimedOut,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorCannotConnectToHost,
             NSURLErrorCannotFindHost,
             NSURLErrorDNSLookupFailed,
             NSURLErrorSecureConnectionFailed:
            return true
        default:
            return false
        }
    }
}

enum TranscriptionConfiguration {
    nonisolated static let model = "gpt-transcribe"
    nonisolated static let requestTimeout: TimeInterval = 120
    nonisolated static let connectionWarmupTimeout: TimeInterval = 10
    nonisolated static let connectionWarmupInterval: TimeInterval = 30
    nonisolated static let legacyModelPreferenceKey = "tt_transcribeModel"

    nonisolated static func languageHints(for selectedLanguage: String) -> [String] {
        switch selectedLanguage {
        case "de", "en":
            return [selectedLanguage]
        default:
            return []
        }
    }

    /// `gpt-transcribe` rejects keywords containing line breaks or angle brackets.
    /// Invalid legacy entries stay in the visible dictionary but are
    /// not sent to the API. Duplicate hints are removed case-insensitively.
    nonisolated static func keywords(from customWords: [String]) -> [String] {
        var seen: Set<String> = []
        return customWords.compactMap { value in
            let keyword = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !keyword.isEmpty,
                  keyword.rangeOfCharacter(from: CharacterSet(charactersIn: "<>\r\n")) == nil
            else { return nil }

            let key = keyword.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "de_DE")
            )
            guard seen.insert(key).inserted else { return nil }
            return keyword
        }
    }

    nonisolated static func removeLegacyModelPreference(from defaults: UserDefaults) {
        defaults.removeObject(forKey: legacyModelPreferenceKey)
    }
}

class TranscriptionService {

    private let session: URLSession
    private let requestBuildQueue = DispatchQueue(
        label: "de.Rehkopf.SPEXT.TranscriptionRequestBuilder",
        qos: .userInitiated
    )
    private let warmupLock = NSLock()
    private var lastWarmupDate: Date?

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// On hotkey press, starts a small read-only model request over the same
    /// URLSession as the later transcription. DNS, TLS and authentication thereby run
    /// in parallel with the recording. A failure intentionally has no effect on the
    /// actual request, which keeps its full error handling.
    func prepareConnection(apiKey: String) {
        let now = Date()
        warmupLock.lock()
        let shouldStart = lastWarmupDate.map {
            now.timeIntervalSince($0) >= TranscriptionConfiguration.connectionWarmupInterval
        } ?? true
        if shouldStart {
            lastWarmupDate = now
        }
        warmupLock.unlock()

        guard shouldStart,
              let request = Self.makeConnectionWarmupRequest(apiKey: apiKey)
        else { return }

        transcriptionLogger.info("Connection warmup begin")
        session.dataTask(with: request) { _, response, error in
            if let error {
                transcriptionLogger.debug(
                    "Connection warmup ended errorCode=\((error as NSError).code, privacy: .public)"
                )
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            transcriptionLogger.info(
                "Connection warmup completed status=\(status, privacy: .public)"
            )
        }.resume()
    }

    nonisolated static func makeConnectionWarmupRequest(apiKey: String) -> URLRequest? {
        guard let url = URL(
            string: "https://api.openai.com/v1/models/\(TranscriptionConfiguration.model)"
        ) else { return nil }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: TranscriptionConfiguration.connectionWarmupTimeout
        )
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    func transcribe(
        audioURL:   URL,
        apiKey:     String,
        language:   String,
        customWords: [String],
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let apiURL = URL(string: "https://api.openai.com/v1/audio/transcriptions") else {
            completion(.failure(SPEXTError.invalidURL)); return
        }

        // All mutable settings are frozen before the queue switch.
        let capturedKey = apiKey
        let capturedLanguage = language
        let capturedWords = customWords
        requestBuildQueue.async { [session] in
            guard let audioData = try? Data(contentsOf: audioURL) else {
                try? FileManager.default.removeItem(at: audioURL)
                completion(.failure(SPEXTError.audioReadFailed))
                return
            }

            let ext = audioURL.pathExtension.lowercased()
            let filename = "audio.\(ext.isEmpty ? "m4a" : ext)"
            let mimeType = ext == "wav" ? "audio/wav" : "audio/m4a"
            let boundary = "SPEXT-\(UUID().uuidString)"
            var request = URLRequest(url: apiURL)
            request.httpMethod = "POST"
            request.setValue("Bearer \(capturedKey)", forHTTPHeaderField: "Authorization")
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = TranscriptionConfiguration.requestTimeout

            let languageHints = TranscriptionConfiguration.languageHints(for: capturedLanguage)
            let keywords = TranscriptionConfiguration.keywords(from: capturedWords)
            let prompt = TranscriptionPromptBuilder.prompt(forLanguage: capturedLanguage)
            request.httpBody = Self.buildBody(
                boundary: boundary,
                audioData: audioData,
                filename: filename,
                mimeType: mimeType,
                languageHints: languageHints,
                keywords: keywords,
                prompt: prompt
            )

            transcriptionLogger.info(
                "Transcription request begin model=\(TranscriptionConfiguration.model, privacy: .public) language=\(capturedLanguage.isEmpty ? "auto" : capturedLanguage, privacy: .public) keywords=\(keywords.count, privacy: .public) bytes=\(audioData.count, privacy: .public)"
            )

            NetworkRetry.dataTask(with: request, session: session) { data, response, error in
                try? FileManager.default.removeItem(at: audioURL)

                if let error = error {
                    transcriptionLogger.error("Transcription request failed error=\(error.localizedDescription, privacy: .public)")
                    completion(.failure(error)); return
                }

                guard let data = data else {
                    transcriptionLogger.error("Transcription request returned empty response")
                    completion(.failure(SPEXTError.emptyResponse)); return
                }

                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    transcriptionLogger.error("Transcription request failed status=\(http.statusCode, privacy: .public)")
                    completion(.failure(Self.parseError(from: data, statusCode: http.statusCode)))
                    return
                }

                guard let text = Self.parseTranscriptionText(from: data) else {
                    transcriptionLogger.error("Transcription response decoding failed")
                    completion(.failure(SPEXTError.decodingFailed)); return
                }
                transcriptionLogger.info("Transcription request completed bytes=\(data.count, privacy: .public)")
                completion(.success(text))
            }
        }
    }

    // MARK: - Parse Errors (incl. Quota Detection)

    static func parseError(from data: Data, statusCode: Int) -> SPEXTError {
        if let json  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any] {
            if let code = error["code"] as? String, code == "insufficient_quota" {
                return .quotaExceeded
            }
            if let type = error["type"] as? String, type == "insufficient_quota" {
                return .quotaExceeded
            }
            if let message = error["message"] as? String {
                return .apiError(message)
            }
        }
        return .apiError(String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "HTTP \(statusCode)")
    }

    nonisolated static func parseTranscriptionText(from data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let text = json["text"] as? String
        else {
            return nil
        }
        return text
    }

    // MARK: - Multipart Body

    nonisolated static func buildBody(
        boundary:      String,
        audioData:     Data,
        filename:      String,
        mimeType:      String,
        languageHints: [String],
        keywords:      [String],
        prompt:        String
    ) -> Data {
        var body = Data()

        func append(_ string: String) {
            if let d = string.data(using: .utf8) { body.append(d) }
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(audioData)
        append("\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append("\(TranscriptionConfiguration.model)\r\n")

        for language in languageHints {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"languages[]\"\r\n\r\n")
            append("\(language)\r\n")
        }

        for keyword in keywords {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"keywords[]\"\r\n\r\n")
            append("\(keyword)\r\n")
        }

        if !prompt.isEmpty {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n")
            append("\(prompt)\r\n")
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        append("json\r\n")

        append("--\(boundary)--\r\n")
        return body
    }
}

// MARK: - Error Types

enum SPEXTError: LocalizedError {
    case invalidURL
    case audioReadFailed
    case emptyResponse
    case encodingFailed
    case decodingFailed
    case quotaExceeded
    case polishOutputTruncated
    case dictionaryOnlyTranscription
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:        return String(localized: "Invalid API URL.")
        case .audioReadFailed:   return String(localized: "Audio file could not be read.")
        case .emptyResponse:     return String(localized: "No response received from the API.")
        case .encodingFailed:    return String(localized: "Request could not be encoded.")
        case .decodingFailed:    return String(localized: "Response could not be decoded.")
        case .quotaExceeded:     return String(localized: "OpenAI credit used up.")
        case .polishOutputTruncated:
            return String(localized: "The rewrite was cut off. Please dictate a shorter text or try again.")
        case .dictionaryOnlyTranscription:
            return String(localized: "The transcription consisted only of dictionary words. The microphone signal was probably empty or too quiet – please record again.")
        case .apiError(let msg): return String(localized: "API error: \(msg)")
        }
    }
}
