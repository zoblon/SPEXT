import Foundation

enum TranscriptionPromptBuilder {
    /// Free-form context for `gpt-transcribe`. Dictionary terms are sent separately as
    /// `keywords[]` so the prompt stays short and in the audio language.
    nonisolated static func prompt(forLanguage language: String) -> String {
        switch language {
        case "de":
            return """
            Kurzes persönliches Diktat auf Deutsch. Transkribiere ausschließlich tatsächlich gesprochene Wörter und erfinde keinen Inhalt. Erhalte Eigennamen, Dateinamen und Fachbegriffe exakt und setze natürliche deutsche Zeichensetzung.
            """
        case "en":
            return """
            Short personal dictation in English. Transcribe only words that were actually spoken and do not invent content. Preserve names, filenames, and technical terms exactly, with natural English punctuation.
            """
        default:
            // OpenAI recommends that the prompt matches the audio language. With true
            // auto-detection no language is known, so it is intentionally left empty.
            return ""
        }
    }
}

enum TranscriptionGuard {
    nonisolated private static let connectorTokens: Set<String> = ["und", "oder", "and", "or"]

    nonisolated static func isDictionaryOnlyResult(_ text: String, customWords: [String]) -> Bool {
        let dictionaryWords = customWords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard dictionaryWords.count >= 2 else { return false }

        let resultTokens = meaningfulTokens(in: text)
        guard resultTokens.count >= 2 else { return false }

        let dictionaryTokenSequence = dictionaryWords.flatMap { meaningfulTokens(in: $0) }
        let dictionaryTokenSet = Set(dictionaryTokenSequence)
        guard !dictionaryTokenSet.isEmpty else { return false }
        guard resultTokens.allSatisfy({ dictionaryTokenSet.contains($0) }) else { return false }

        let matchedWords = dictionaryWords.filter { word in
            containsSubsequence(meaningfulTokens(in: word), in: resultTokens)
        }.count
        let minimumMatchedWords = min(dictionaryWords.count, max(3, Int(ceil(Double(dictionaryWords.count) * 0.6))))
        return matchedWords >= minimumMatchedWords
    }

    private nonisolated static func meaningfulTokens(in value: String) -> [String] {
        normalizedTokens(in: value).filter { !connectorTokens.contains($0) }
    }

    private nonisolated static func normalizedTokens(in value: String) -> [String] {
        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
        var tokens: [String] = []
        var current = ""

        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }

    private nonisolated static func containsSubsequence(_ needle: [String], in haystack: [String]) -> Bool {
        guard !needle.isEmpty, needle.count <= haystack.count else { return false }

        for startIndex in 0...(haystack.count - needle.count) {
            if Array(haystack[startIndex..<(startIndex + needle.count)]) == needle {
                return true
            }
        }
        return false
    }
}

enum RecordingQuality {
    /// Level (already scaled *25, 0…1) above which a single buffer counts as "voiced".
    /// Real speech saturates the level well above this value; the
    /// noise floor of an (HFP) microphone stays below it.
    /// Also used in the recorder's tap callback to count `voicedFrames`.
    nonisolated static let speechLevelThreshold: Float = 0.12

    /// Minimum peak level required to assume a usable signal at all.
    nonisolated private static let minimumPeakAudioLevel: Float = 0.12

    /// Minimum share of voiced frames among all written frames.
    /// Over a ≥1s recording this corresponds to a minimum speech duration and filters out
    /// single clicks/spikes that are only briefly above the speech threshold.
    nonisolated private static let minimumVoicedRatio: Float = 0.05

    /// Decides whether a recording contains a real speech signal.
    ///
    /// Important against transcription hallucinations: with silence (key held, but nothing
    /// said) the model otherwise invents plausible-sounding but fabricated sentences.
    /// A single peak level is not sufficient as a criterion – noise/clicks can
    /// exceed it. Hence the additional share of actually voiced frames.
    nonisolated static func hasMeaningfulSpeech(
        peakAudioLevel: Float,
        voicedFrames: Int,
        totalFrames: Int
    ) -> Bool {
        guard totalFrames > 0 else { return false }
        guard peakAudioLevel >= minimumPeakAudioLevel else { return false }
        let voicedRatio = Float(voicedFrames) / Float(totalFrames)
        return voicedRatio >= minimumVoicedRatio
    }
}

enum RecordingLimits {
    nonisolated static let maximumDuration: TimeInterval = 10 * 60
}

enum CustomWordList {
    nonisolated private static let invalidKeywordCharacters = CharacterSet(charactersIn: "<>\r\n")

    nonisolated static func adding(_ value: String, to words: [String]) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return words }
        guard trimmed.rangeOfCharacter(from: invalidKeywordCharacters) == nil else { return words }
        guard !containsEquivalentWord(trimmed, in: words) else { return words }
        return words + [trimmed]
    }

    nonisolated static func replacing(original: String, with value: String, in words: [String]) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.rangeOfCharacter(from: invalidKeywordCharacters) == nil,
              let index = words.firstIndex(of: original)
        else { return words }

        let originalKey = normalizedKey(original)
        let replacementKey = normalizedKey(trimmed)
        guard replacementKey != originalKey else { return words }

        let duplicatesAnotherWord = words.enumerated().contains { offset, word in
            offset != index && normalizedKey(word) == replacementKey
        }
        guard !duplicatesAnotherWord else { return words }

        var updated = words
        updated[index] = trimmed
        return updated
    }

    private nonisolated static func containsEquivalentWord(_ value: String, in words: [String]) -> Bool {
        let key = normalizedKey(value)
        return words.contains { normalizedKey($0) == key }
    }

    private nonisolated static func normalizedKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
    }
}
