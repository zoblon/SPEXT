import AppKit
import ApplicationServices

/// Memory-only snapshot. No field text is logged, persisted or sent to an API.
struct FocusedFieldSnapshot {
    let context: InsertionContext
    fileprivate let processIdentifier: pid_t
    fileprivate let element: AXUIElement
    fileprivate let selection: NSRange
    fileprivate let reportedLength: Int

    /// Call immediately before posting Cmd+V. AX has no atomic read-and-paste operation.
    /// Changes outside the bounded windows with unchanged length cannot be detected.
    func isCurrent() -> Bool {
        guard let current = FocusedFieldReader.capture(processIdentifier: processIdentifier) else { return false }
        return CFEqual(element, current.element)
            && selection == current.selection
            && reportedLength == current.reportedLength
            && context == current.context
    }
}

enum FocusedFieldReader {
    /// Best effort only: unsupported, secure, stale or malformed fields have no context.
    /// Only the currently focused text element of the foreground target app is queried.
    static func capture(processIdentifier: pid_t) -> FocusedFieldSnapshot? {
        guard processIdentifier > 0, AXIsProcessTrusted(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == processIdentifier else { return nil }

        let application = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.15)
        guard let focused = attribute(application, kAXFocusedUIElementAttribute),
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.15)
        var elementPID: pid_t = 0
        guard AXUIElementGetPid(element, &elementPID) == .success,
              elementPID == processIdentifier,
              let role = attribute(element, kAXRoleAttribute) as? String else { return nil }

        // Role and subrole are checked before requesting any text or range values.
        // Unsupported subroles are normal for ordinary text areas; transport failures
        // are not permission to read a field whose security status is unknown.
        var subroleValue: CFTypeRef?
        let subroleResult = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue)
        guard subroleResult == .success || subroleResult == .attributeUnsupported || subroleResult == .noValue else { return nil }
        guard subroleValue == nil || subroleValue is String,
              FocusedFieldPolicy.isEligible(role: role, subrole: subroleValue as? String) else { return nil }
        if let enabled = attribute(element, kAXEnabledAttribute) as? Bool, !enabled { return nil }
        if let editable = attribute(element, kAXIsEditableAttribute) as? Bool, !editable { return nil }

        guard let length = characterCount(element), let selection = selectedRange(element),
              let ranges = FocusedFieldPolicy.ranges(length: length, selection: selection) else { return nil }

        let context: InsertionContext?
        if let before = stringUnits(element, range: ranges.before),
           let after = stringUnits(element, range: ranges.after) {
            context = FocusedFieldPolicy.context(beforeUTF16: before, afterUTF16: after)
        } else {
            // Never ask for AXValue unless the field itself reported a small length.
            guard FocusedFieldPolicy.permitsValueFallback(reportedLength: length),
                  let value = attribute(element, kAXValueAttribute),
                  let units = utf16Units(value, expectedLength: length) else { return nil }
            context = FocusedFieldPolicy.context(
                beforeUTF16: Array(units[ranges.before.location..<(ranges.before.location + ranges.before.length)]),
                afterUTF16: Array(units[ranges.after.location..<(ranges.after.location + ranges.after.length)])
            )
        }
        // Read metadata again to refuse movement/edits during the multi-call read itself.
        guard let context, characterCount(element) == length, selectedRange(element) == selection,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == processIdentifier,
              let currentFocus = attribute(application, kAXFocusedUIElementAttribute),
              CFEqual(element, currentFocus) else { return nil }
        return FocusedFieldSnapshot(context: context, processIdentifier: processIdentifier,
                                    element: element, selection: selection, reportedLength: length)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func characterCount(_ element: AXUIElement) -> Int? {
        guard let value = attribute(element, kAXNumberOfCharactersAttribute),
              CFGetTypeID(value) == CFNumberGetTypeID() else { return nil }
        var count: Int64 = 0
        guard CFNumberGetValue((value as! CFNumber), .sInt64Type, &count),
              count >= 0, count <= Int.max else { return nil }
        return Int(count)
    }

    private static func selectedRange(_ element: AXUIElement) -> NSRange? {
        guard let value = attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let rangeValue = value as! AXValue
        guard AXValueGetType(rangeValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    private static func stringUnits(_ element: AXUIElement, range: NSRange) -> [UInt16]? {
        guard range.length > 0 else { return [] }
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let parameter = AXValueCreate(.cfRange, &cfRange) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString,
                                                         parameter, &value) == .success, let value else { return nil }
        return utf16Units(value, expectedLength: range.length)
    }

    private static func utf16Units(_ value: CFTypeRef, expectedLength: Int) -> [UInt16]? {
        guard CFGetTypeID(value) == CFStringGetTypeID() else { return nil }
        let string = value as! CFString
        guard CFStringGetLength(string) == expectedLength else { return nil }
        var units = [UInt16](repeating: 0, count: expectedLength)
        if expectedLength > 0 { CFStringGetCharacters(string, CFRange(location: 0, length: expectedLength), &units) }
        return units
    }
}

/// Pure policy keeps range/UTF-16 validation testable without inspecting other apps.
enum FocusedFieldPolicy {
    nonisolated static func isEligible(role: String, subrole: String?) -> Bool {
        let identity = (role + " " + (subrole ?? "")).lowercased()
        guard !identity.contains("secure"), !identity.contains("password") else { return false }
        return role == "AXTextField" || role == "AXTextArea"
    }

    nonisolated static func ranges(length: Int, selection: NSRange) -> (before: NSRange, after: NSRange)? {
        guard length >= 0, selection.location >= 0, selection.length >= 0,
              selection.location != NSNotFound, selection.location <= length,
              selection.length <= length - selection.location else { return nil }
        let end = selection.location + selection.length
        let beforeLength = min(selection.location, 256)
        return (NSRange(location: selection.location - beforeLength, length: beforeLength),
                NSRange(location: end, length: min(length - end, 256)))
    }

    nonisolated static func permitsValueFallback(reportedLength: Int) -> Bool {
        (0...4_096).contains(reportedLength)
    }

    nonisolated static func context(beforeUTF16: [UInt16], afterUTF16: [UInt16]) -> InsertionContext? {
        var before = beforeUTF16
        var after = afterUTF16
        // The outer window edge may split a pair; the cursor-facing edge must not.
        if let first = before.first, isLowSurrogate(first) { before.removeFirst() }
        if let last = after.last, isHighSurrogate(last) { after.removeLast() }
        guard isValidUTF16(before), isValidUTF16(after) else { return nil }
        return InsertionContext(before: String(decoding: before, as: UTF16.self),
                                after: String(decoding: after, as: UTF16.self))
    }

    nonisolated private static func isValidUTF16(_ units: [UInt16]) -> Bool {
        var index = 0
        while index < units.count {
            if isHighSurrogate(units[index]) {
                guard index + 1 < units.count, isLowSurrogate(units[index + 1]) else { return false }
                index += 2
            } else {
                guard !isLowSurrogate(units[index]) else { return false }
                index += 1
            }
        }
        return true
    }

    nonisolated private static func isHighSurrogate(_ unit: UInt16) -> Bool { (0xD800...0xDBFF).contains(unit) }
    nonisolated private static func isLowSurrogate(_ unit: UInt16) -> Bool { (0xDC00...0xDFFF).contains(unit) }
}
