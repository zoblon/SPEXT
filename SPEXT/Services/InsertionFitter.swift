import Foundation

/// A short, local view of the text on either side of the selection being replaced.
/// The selected text itself is deliberately excluded.
struct InsertionContext: Equatable {
    let before: String
    let after: String
}

enum InsertionFitter {
    /// Adjusts only insertion boundaries. Context never changes spelling, case or language.
    nonisolated static func fit(_ text: String, context: InsertionContext?) -> String {
        guard let context else { return text + " " }
        var fitted = text
        // Keep newlines (including CRLF) and internal indentation exactly as supplied.
        while let first = fitted.first, isHorizontalWhitespace(first) { fitted.removeFirst() }
        while let last = fitted.last, isHorizontalWhitespace(last) { fitted.removeLast() }
        guard !fitted.isEmpty else { return "" }

        // Collapse only an identical, isolated punctuation mark at the exact seam.
        // Runs such as ellipses, ?? and ?! carry meaning and must survive unchanged.
        if let first = fitted.first, first == context.before.last,
           first != "…", isPunctuation(first), isolatedAtStart(fitted), isolatedAtEnd(context.before) {
            fitted.removeFirst()
        }
        if let last = fitted.last, last == context.after.first,
           last != "…", isPunctuation(last), isolatedAtEnd(fitted), isolatedAtStart(context.after) {
            fitted.removeLast()
        }
        guard !fitted.isEmpty else { return "" }

        let leadingSpace = needsSpace(left: context.before, right: fitted)
        let trailingSpace: Bool
        if context.after.isEmpty {
            trailingSpace = fitted.last.map { !$0.isWhitespace } == true
                && !endsWithOpeningDelimiter(fitted)
        } else {
            trailingSpace = needsSpace(left: fitted, right: context.after)
        }
        return (leadingSpace ? " " : "") + fitted + (trailingSpace ? " " : "")
    }

    nonisolated private static func needsSpace(left: String, right: String) -> Bool {
        guard let previous = left.last, let next = right.first,
              !previous.isWhitespace, !next.isWhitespace else { return false }
        if endsWithOpeningDelimiter(left) || startsWithClosingDelimiter(right) { return false }
        if isPunctuation(next) { return false }
        return true
    }

    nonisolated private static func endsWithOpeningDelimiter(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        if "([{»„".contains(last) { return true }
        if "\"'“‘".contains(last) {
            return text.dropLast().last.map { $0.isWhitespace || "([{».:;!?".contains($0) } ?? true
        }
        return false
    }

    nonisolated private static func startsWithClosingDelimiter(_ text: String) -> Bool {
        guard let first = text.first else { return false }
        if ")]}«”’".contains(first) { return true }
        if "\"'“".contains(first) {
            return text.dropFirst().first.map { $0.isWhitespace || isPunctuation($0) || ")]}«”’".contains($0) } ?? true
        }
        return false
    }

    nonisolated private static func isHorizontalWhitespace(_ character: Character) -> Bool {
        character.isWhitespace && !character.isNewline
    }

    nonisolated private static func isPunctuation(_ character: Character) -> Bool {
        ".,;:!?…".contains(character)
    }

    nonisolated private static func isolatedAtStart(_ text: String) -> Bool {
        text.dropFirst().first.map { !isPunctuation($0) } ?? true
    }

    nonisolated private static func isolatedAtEnd(_ text: String) -> Bool {
        text.dropLast().last.map { !isPunctuation($0) } ?? true
    }
}
