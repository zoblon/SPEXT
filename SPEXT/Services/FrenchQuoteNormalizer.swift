import Foundation
import NaturalLanguage

/// Converts double quotation marks into inward-pointing French quotes (»…«),
/// the style used for German text.
///
/// The conversion depends on the **dictation language** (the "Sprache" setting and the
/// transcript itself), never on the interface language: an English dictation must keep
/// its quotation marks.
enum FrenchQuoteNormalizer {
    /// Minimum confidence of the German hypothesis before a transcript counts as clearly
    /// German when the language setting is "automatic".
    nonisolated static let minimumGermanConfidence = 0.9

    /// Applies the conversion only when the dictation is German: the setting is German
    /// (`"de"`), or – with automatic detection (`""`) – the text is clearly German.
    /// English and any other or unclear case keep the text unchanged.
    nonisolated static func normalize(_ text: String, dictationLanguage: String) -> String {
        guard isGerman(text, dictationLanguage: dictationLanguage) else { return text }
        return normalize(text)
    }

    nonisolated static func isGerman(_ text: String, dictationLanguage: String) -> Bool {
        switch dictationLanguage {
        case "de":
            return true
        case "":
            return isClearlyGerman(text)
        default:
            return false
        }
    }

    /// `true` only if the language recognizer is confident that the text is German.
    /// Short or ambiguous text yields `false` so that nothing is converted by mistake.
    nonisolated static func isClearlyGerman(_ text: String) -> Bool {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 2)
        guard let best = hypotheses.max(by: { $0.value < $1.value }),
              best.key == .german else { return false }
        return best.value >= minimumGermanConfidence
    }

    nonisolated static func normalize(_ text: String) -> String {
        var result = ""
        var isInsideQuote = false

        for character in text {
            switch character {
            case "\"", "„", "“", "”", "«", "»":
                result.append(isInsideQuote ? "«" : "»")
                isInsideQuote.toggle()
            default:
                result.append(character)
            }
        }

        return result
    }
}
