import CoreGraphics
import Foundation

enum HotkeySettings {
    static let leftDirectDefaultRaw = Int(
        CGEventFlags(rawValue: CGEventFlags([.maskAlternate, .maskCommand]).rawValue | 0x00000008 | 0x00000020).rawValue
    )
    static let leftPolishDefaultRaw = Int(
        CGEventFlags(rawValue: CGEventFlags([.maskControl, .maskAlternate]).rawValue | 0x00000001 | 0x00000020).rawValue
    )
    static let generalDirectDefaultRaw = Int(CGEventFlags([.maskAlternate, .maskCommand]).rawValue)
    static let generalPolishDefaultRaw = Int(CGEventFlags([.maskControl, .maskAlternate]).rawValue)

    static let defaultDirectRaw = Int(
        CGEventFlags(rawValue: CGEventFlags([.maskAlternate, .maskCommand]).rawValue | 0x00000010 | 0x00000040).rawValue
    )
    static let defaultPolishRaw = Int(
        CGEventFlags(rawValue: CGEventFlags([.maskControl, .maskAlternate]).rawValue | 0x00002000 | 0x00000040).rawValue
    )

    static let generalModifiers: CGEventFlags = [
        .maskControl, .maskAlternate, .maskShift, .maskCommand
    ]

    static let deviceModifiersMask: CGEventFlags = CGEventFlags(rawValue:
        0x00000001 | 0x00000002 | 0x00000004 | 0x00000008 |
        0x00000010 | 0x00000020 | 0x00000040 | 0x00002000
    )

    static let knownModifiers: CGEventFlags = CGEventFlags(rawValue:
        generalModifiers.rawValue | deviceModifiersMask.rawValue
    )

    static func normalizedStoredRaw(_ raw: Int) -> Int {
        switch raw {
        case generalDirectDefaultRaw:
            return defaultDirectRaw
        case generalPolishDefaultRaw:
            return defaultPolishRaw
        default:
            return raw
        }
    }

    static func matches(current rawCurrent: CGEventFlags, trigger triggerFlags: CGEventFlags) -> Bool {
        let current = rawCurrent.intersection(knownModifiers)

        if triggerFlags.intersection(deviceModifiersMask).isEmpty {
            return current.intersection(generalModifiers) == triggerFlags
        } else {
            return current == triggerFlags
        }
    }
}
