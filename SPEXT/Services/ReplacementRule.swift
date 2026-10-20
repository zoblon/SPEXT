import Foundation

nonisolated struct ReplacementRule: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var spoken: String
    var written: String

    nonisolated init(id: UUID = UUID(), spoken: String, written: String) {
        self.id = id
        self.spoken = spoken
        self.written = written
    }
}

/// Local, literal substitutions. Matching always reads the original transcript, never its output.
nonisolated enum ReplacementRules {
    enum ValidationIssue: Equatable, Sendable {
        case emptySpoken
        case emptyWritten
        case lineBreak
        case duplicateSpoken

    }

    nonisolated static func validationIssue(
        for rule: ReplacementRule,
        among rules: [ReplacementRule],
        excludingID: UUID? = nil
    ) -> ValidationIssue? {
        if let issue = contentIssue(for: rule) { return issue }
        let key = normalizedSpoken(rule.spoken)
        if rules.contains(where: {
            $0.id != excludingID && contentIssue(for: $0) == nil
                && normalizedSpoken($0.spoken) == key
        }) {
            return .duplicateSpoken
        }
        return nil
    }

    nonisolated static func applying(_ text: String, rules: [ReplacementRule]) -> String {
        let candidates = rules.filter { contentIssue(for: $0) == nil }
        let counts = Dictionary(grouping: candidates, by: { normalizedSpoken($0.spoken) })
        let validRules = candidates.filter { counts[normalizedSpoken($0.spoken)]?.count == 1 }
            .sorted { normalizedSpoken($0.spoken).utf16.count > normalizedSpoken($1.spoken).utf16.count }
        guard !validRules.isEmpty else { return text }

        // Marks are included so a decomposed accent never creates a false word boundary.
        let wordCharacter = "[\\p{L}\\p{M}\\p{N}_]"
        let alternatives = validRules.map { rule in
            let term = rule.spoken.split(whereSeparator: { $0.isWhitespace })
                .map { literalPattern(for: String($0)) }
                .joined(separator: "\\s+")
            return "(\(term))"
        }
        let pattern = "(?<!\(wordCharacter))(?:\(alternatives.joined(separator: "|")))(?!\(wordCharacter))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }

        let original = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: original.length))
        guard !matches.isEmpty else { return text }
        var result = ""
        var cursor = 0
        for match in matches {
            guard let index = validRules.indices.first(where: {
                match.range(at: $0 + 1).location != NSNotFound
            }) else { continue }
            result += original.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            // Do not use a regex replacement template: dollars and backslashes are user text.
            result += validRules[index].written
            cursor = NSMaxRange(match.range)
        }
        result += original.substring(from: cursor)
        return result
    }

    nonisolated private static func literalPattern(for token: String) -> String {
        token.map { character in
            let literal = String(character)
            let composed = NSRegularExpression.escapedPattern(for: literal.precomposedStringWithCanonicalMapping)
            let decomposed = NSRegularExpression.escapedPattern(for: literal.decomposedStringWithCanonicalMapping)
            // Swift String equality treats these as equal; compare UTF-16 to detect the alternate spelling.
            if Array(composed.utf16) == Array(decomposed.utf16) { return composed }
            return "(?:\(composed)|\(decomposed))"
        }.joined()
    }

    nonisolated private static func contentIssue(for rule: ReplacementRule) -> ValidationIssue? {
        if rule.spoken.rangeOfCharacter(from: .newlines) != nil
            || rule.written.rangeOfCharacter(from: .newlines) != nil { return .lineBreak }
        if rule.spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .emptySpoken }
        if rule.written.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .emptyWritten }
        return nil
    }

    nonisolated private static func normalizedSpoken(_ spoken: String) -> String {
        spoken.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .precomposedStringWithCanonicalMapping
    }
}
