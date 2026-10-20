import Foundation

private func expectReplacement(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: Replacement rules: \(message)\n", stderr)
        exit(1)
    }
}

/// Foundation-only tests also run from the main guard-test runner.
enum ReplacementRuleTests {
    static func run() {
        testLiteralMatching()
        testLongestMatchAndSinglePass()
        testBoundariesAndUnicode()
        testWhitespaceAndPreservation()
        testValidationAndMalformedRules()
        testJSONRoundTrip()
        print("PASS: Replacement rules")
    }

    private static func testLiteralMatching() {
        let rules = [ReplacementRule(spoken: "mirko", written: "Mirco")]
        expectReplacement(ReplacementRules.applying("Hallo MIRKO, mirko!", rules: rules) == "Hallo Mirco, Mirco!", "whole terms match case-insensitively")
        let literal = [ReplacementRule(spoken: "C++ (team)", written: "$1\\project $0")]
        expectReplacement(ReplacementRules.applying("C++ (team); C++ team", rules: literal) == "$1\\project $0; C++ team", "regex syntax and replacement dollar/backslash stay literal")
        expectReplacement(ReplacementRules.applying("Any text", rules: []) == "Any text", "empty rules preserve input")
    }

    private static func testLongestMatchAndSinglePass() {
        let rules = [
            ReplacementRule(spoken: "New", written: "N"),
            ReplacementRule(spoken: "New York", written: "NYC"),
            ReplacementRule(spoken: "New York City", written: "NY"),
            ReplacementRule(spoken: "NY", written: "expanded")
        ]
        expectReplacement(ReplacementRules.applying("New York City, New York, New, NY", rules: rules) == "NY, NYC, N, expanded", "longest overlap wins and generated text is never matched again")
        expectReplacement(ReplacementRules.applying("New York City", rules: rules.reversed()) == "NY", "longest match is independent of rule order")
        let cycle = [ReplacementRule(spoken: "a", written: "b"), ReplacementRule(spoken: "b", written: "a")]
        expectReplacement(ReplacementRules.applying("a b", rules: cycle) == "b a", "cycles do not cascade")
    }

    private static func testBoundariesAndUnicode() {
        let rules = [ReplacementRule(spoken: "Anna", written: "Anne")]
        expectReplacement(ReplacementRules.applying("Anna Annabelle xAnna Anna2 2Anna Anna_x x_Anna (Anna) Anna-Anna", rules: rules) == "Anne Annabelle xAnna Anna2 2Anna Anna_x x_Anna (Anne) Anne-Anne", "letters, digits and underscores prevent partial word matches")
        expectReplacement(ReplacementRules.applying("éAnna Annaé 中Anna Anna中 Anna\u{0301}", rules: rules) == "éAnna Annaé 中Anna Anna中 Anna\u{0301}", "Unicode letters and combining marks belong to word boundaries")
        let names = [ReplacementRule(spoken: "JÖRG MÜLLER", written: "Jörg Müller"), ReplacementRule(spoken: "Σοφία", written: "Sofia")]
        expectReplacement(ReplacementRules.applying("jörg müller und ΣΟΦΊΑ 😀", rules: names) == "Jörg Müller und Sofia 😀", "Unicode names match ignoring case while emoji survive")
        expectReplacement(ReplacementRules.applying("😀 jo\u{0308}rg mu\u{0308}ller", rules: names) == "😀 Jörg Müller", "canonically decomposed names match without disturbing UTF-16 offsets")
    }

    private static func testWhitespaceAndPreservation() {
        let rules = [ReplacementRule(spoken: "  side   click  ", written: "Sideklick")]
        expectReplacement(ReplacementRules.applying("\tSIDE\t click / side\nclick / side\u{00A0}click  \n", rules: rules) == "\tSideklick / Sideklick / Sideklick  \n", "spoken whitespace is flexible and outside whitespace is preserved")
        expectReplacement(ReplacementRules.applying("sideclick / side clicker", rules: rules) == "sideclick / side clicker", "a spoken whitespace gap cannot disappear")
        let explicitSpaces = [ReplacementRule(spoken: "word", written: "  $word\\  ")]
        expectReplacement(ReplacementRules.applying("(word)", rules: explicitSpaces) == "(  $word\\  )", "written content is inserted exactly as entered")
        expectReplacement(ReplacementRules.applying("No  editorial\ncleanup?!", rules: rules) == "No  editorial\ncleanup?!", "unmatched text is untouched")
    }

    private static func testValidationAndMalformedRules() {
        let valid = ReplacementRule(spoken: "side click", written: "Sideklick")
        expectReplacement(ReplacementRules.validationIssue(for: valid, among: []) == nil, "valid rule accepted")
        expectReplacement(ReplacementRules.validationIssue(for: ReplacementRule(spoken: " \t", written: "x"), among: []) == .emptySpoken, "blank spoken form rejected")
        expectReplacement(ReplacementRules.validationIssue(for: ReplacementRule(spoken: "x", written: " \t"), among: []) == .emptyWritten, "blank replacement rejected")
        for lineBreak in ["\n", "\r", "\u{2028}", "\u{2029}"] {
            expectReplacement(ReplacementRules.validationIssue(for: ReplacementRule(spoken: "a\(lineBreak)b", written: "x"), among: []) == .lineBreak, "spoken line breaks rejected")
            expectReplacement(ReplacementRules.validationIssue(for: ReplacementRule(spoken: "x", written: "a\(lineBreak)b"), among: []) == .lineBreak, "written line breaks rejected")
        }
        let duplicate = ReplacementRule(spoken: "  SIDE\tCLICK ", written: "other")
        expectReplacement(ReplacementRules.validationIssue(for: duplicate, among: [valid]) == .duplicateSpoken, "case and whitespace duplicates rejected")
        expectReplacement(ReplacementRules.validationIssue(for: valid, among: [valid], excludingID: valid.id) == nil, "editing a rule does not collide with itself")
        let malformed = [ReplacementRule(spoken: "", written: "everything"), ReplacementRule(spoken: "erase", written: " "), ReplacementRule(spoken: "bad\nrule", written: "x"), valid, duplicate]
        expectReplacement(ReplacementRules.applying("erase side click bad\nrule", rules: malformed) == "erase side click bad\nrule", "malformed and all ambiguous duplicate rules are ignored")
        let good = ReplacementRule(spoken: "good", written: "safe")
        expectReplacement(ReplacementRules.applying("good side click", rules: malformed + [good]) == "safe side click", "malformed neighbors do not block valid rules")
        let canonicalDuplicate = ReplacementRule(spoken: "mu\u{0308}ller", written: "other")
        expectReplacement(ReplacementRules.validationIssue(for: canonicalDuplicate, among: [ReplacementRule(spoken: "Müller", written: "name")]) == .duplicateSpoken, "canonically equivalent Unicode duplicate rejected")
    }

    private static func testJSONRoundTrip() {
        let original = [ReplacementRule(spoken: "größer", written: "Größer $1\\"), ReplacementRule(spoken: "hello", written: "Hallo")]
        do {
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode([ReplacementRule].self, from: data)
            expectReplacement(decoded == original, "JSON preserves identity and exact strings")
            expectReplacement(decoded[0].id != decoded[1].id, "default IDs are unique")
        } catch {
            expectReplacement(false, "JSON roundtrip failed: \(error)")
        }
    }
}
