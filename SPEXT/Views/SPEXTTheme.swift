import SwiftUI

/// Warm neutral surfaces keep the blue-violet identity focused on interaction.
enum SPEXTTheme {
    static let canvas = adaptive(light: 0xF5F3EE, dark: 0x242421)
    static let surface = adaptive(light: 0xFEFDF9, dark: 0x2E2E2A)
    static let accent = adaptive(light: 0x555AB6, dark: 0xA7ABF0)
    static let rule = adaptive(light: 0xDEDDD5, dark: 0x45453F)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((value >> 16) & 255) / 255,
                           green: Double((value >> 8) & 255) / 255,
                           blue: Double(value & 255) / 255, alpha: 1)
        })
    }
}
