import Foundation

enum InsertionFitterTests {
    private static var failureCount = 0

    static func run() {
        failureCount = 0
        // These literal fixtures catch lost spaces, intrusive spaces, punctuation loss,
        // accidental rewriting and newline stripping at the actual insertion boundary.
        let cases: [(String, String, String, String)] = [
            ("world", "Hello", "", " world "),
            ("Welt", "Hallo ", "", "Welt "),
            ("world", "Hello", " again", " world"),
            ("middle", "left", "right", " middle "),
            ("replacement", "before ", " after", "replacement"),
            ("hello", "", "", "hello "),
            ("hello", "\n", "", "hello "),
            ("hello", "\r\n", "\nnext", "hello"),
            ("hello", "  ", "\t", "hello"),
            ("  hello  ", "before ", " after", "hello"),
            ("hello\n", "", "", "hello\n"),
            ("\nhello", "before", "", "\nhello "),
            ("hello\n\n", "", "next", "hello\n\n"),
            ("hello", "(", ")", "hello"),
            ("hello", "[", "]", "hello"),
            ("hello", "{", "}", "hello"),
            ("hello", "»", "«", "hello"),
            ("hello", "„", "“", "hello"),
            ("hello", "“", "”", "hello"),
            ("hello", "He said \"", "\".", "hello"),
            ("hello", "He said \"yes\"", "", " hello "),
            ("weiter", "»fertig«", "", " weiter "),
            ("next", "done)", "", " next "),
            ("hello", "", ", next", "hello"),
            ("hello", "", ".", "hello"),
            ("hello.", "", ". Next", "hello"),
            ("hello!", "", "! Next", "hello"),
            ("hello?", "", "? Next", "hello"),
            (". Next", "Done.", "", " Next "),
            ("! Next", "Done!", "", " Next "),
            ("hello...", "", ".", "hello..."),
            ("hello.", "", "...", "hello."),
            ("... Next", "Done.", "", "... Next "),
            ("hello??", "", "?", "hello??"),
            ("hello?!", "", "!", "hello?!"),
            ("hello!", "", "!?", "hello!"),
            ("hello…", "", "…", "hello…"),
            ("ok", "👩🏽‍💻", "🚀", " ok "),
            ("iPhone bleibt iPhone", "", "", "iPhone bleibt iPhone "),
            ("", "word", "word", ""),
            (" ", "word", "word", ""),
            ("\n", "word", "word", "\n")
        ]
        for (text, before, after, expected) in cases {
            let actual = InsertionFitter.fit(text, context: InsertionContext(before: before, after: after))
            expect(actual == expected, "fit \(text.debugDescription) between \(before.debugDescription) / \(after.debugDescription): expected \(expected.debugDescription), got \(actual.debugDescription)")
        }
        expect(InsertionFitter.fit("hello", context: nil) == "hello ", "Unavailable context keeps literal trailing-space behavior")
        expect(InsertionFitter.fit("hello ", context: nil) == "hello  ", "Fallback does not normalize literal whitespace")
        expect(InsertionFitter.fit("hello\n", context: nil) == "hello\n ", "Fallback preserves literal newline")

        testBoundedFieldPolicy()
        if failureCount > 0 { exit(1) }
        print("Insertion fitting and bounded field policy tests passed")
    }

    private static func testBoundedFieldPolicy() {
        expect(FocusedFieldPolicy.isEligible(role: "AXTextArea", subrole: nil), "Ordinary text areas are eligible")
        expect(FocusedFieldPolicy.isEligible(role: "AXTextField", subrole: "AXSearchField"), "Search fields are text")
        expect(!FocusedFieldPolicy.isEligible(role: "AXTextField", subrole: "AXSecureTextField"), "Secure fields are excluded before text reads")
        expect(!FocusedFieldPolicy.isEligible(role: "AXTextField", subrole: "AXPasswordField"), "Password variants are excluded")
        expect(!FocusedFieldPolicy.isEligible(role: "AXButton", subrole: nil), "Nontext elements are excluded")

        let ranges = FocusedFieldPolicy.ranges(length: 10_000, selection: NSRange(location: 5_000, length: 20))
        expect(ranges?.before == NSRange(location: 4_744, length: 256), "Before read is bounded in large fields")
        expect(ranges?.after == NSRange(location: 5_020, length: 256), "After read excludes selection and stays bounded")
        let empty = FocusedFieldPolicy.ranges(length: 0, selection: NSRange(location: 0, length: 0))
        expect(empty?.before == NSRange(location: 0, length: 0) && empty?.after == NSRange(location: 0, length: 0), "Empty fields have valid empty ranges")
        expect(FocusedFieldPolicy.ranges(length: 10, selection: NSRange(location: 9, length: 2)) == nil, "Out-of-bounds selections are refused")
        expect(FocusedFieldPolicy.ranges(length: 10, selection: NSRange(location: NSNotFound, length: 0)) == nil, "Missing selection is refused")
        expect(FocusedFieldPolicy.ranges(length: 10, selection: NSRange(location: -1, length: 0)) == nil, "Negative selection location is refused")
        expect(FocusedFieldPolicy.ranges(length: 10, selection: NSRange(location: 0, length: -1)) == nil, "Negative selection length is refused")
        expect(FocusedFieldPolicy.ranges(length: Int.max, selection: NSRange(location: Int.max - 1, length: 3)) == nil, "Overflowing selection is refused without adding its endpoints")
        expect(!FocusedFieldPolicy.permitsValueFallback(reportedLength: 4_097), "Large fields never request full values")
        expect(!FocusedFieldPolicy.permitsValueFallback(reportedLength: -1), "Invalid length never permits a value read")
        expect(FocusedFieldPolicy.permitsValueFallback(reportedLength: 4_096), "Small reported values permit bounded fallback")

        let emoji: [UInt16] = [0xD83D, 0xDE80]
        expect(FocusedFieldPolicy.context(beforeUTF16: emoji, afterUTF16: emoji) == InsertionContext(before: "🚀", after: "🚀"), "Surrogate pairs are preserved")
        expect(FocusedFieldPolicy.context(beforeUTF16: [0xDE80, 65], afterUTF16: [66, 0xD83D]) == InsertionContext(before: "A", after: "B"), "Only partial outer surrogate pairs are discarded")
        expect(FocusedFieldPolicy.context(beforeUTF16: [65, 0xD83D], afterUTF16: []) == nil, "Cursor inside a surrogate pair is refused")
        expect(FocusedFieldPolicy.context(beforeUTF16: [], afterUTF16: [0xDE80, 66]) == nil, "Selection endpoint inside a surrogate pair is refused")
        expect(FocusedFieldPolicy.context(beforeUTF16: [65, 0xD83D, 66], afterUTF16: []) == nil, "Malformed interior UTF-16 is refused")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            failureCount += 1
        }
    }
}
