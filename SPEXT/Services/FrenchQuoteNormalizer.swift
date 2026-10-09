import Foundation

enum FrenchQuoteNormalizer {
    static func normalize(_ text: String) -> String {
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
