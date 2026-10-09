import Foundation

/// User-facing status and error texts shown in the menu bar popover.
/// All texts are localized through the string catalog (`Localizable.xcstrings`).
enum AppStatusText {
    // MARK: Status line

    static let ready = String(localized: "Ready")
    static let noAPIKey = String(localized: "No API key")
    static let recording = String(localized: "Recording…")
    static let recordingMessage = String(localized: "Recording (message)…")
    static let preparingRecording = String(localized: "Preparing recording…")
    static let transcribing = String(localized: "Transcribing…")
    static let rewriting = String(localized: "Rewriting…")
    static let pasted = String(localized: "Pasted")
    static let checkText = String(localized: "Check text")
    static let dictationSaved = String(localized: "Dictation saved")
    static let recordingLimitReached = String(localized: "Recording limit reached")
    static let microphoneError = String(localized: "Microphone error")
    static let recordingError = String(localized: "Recording error")
    static let keychainError = String(localized: "Keychain error")
    static let noCredit = String(localized: "No credit")
    static let error = String(localized: "Error")
    static let pasteBlocked = String(localized: "Paste blocked")
    static let hotkeysBlocked = String(localized: "Hotkeys blocked")

    // MARK: Error and explanation texts

    static let apiKeyMissing = String(localized: "Please enter your OpenAI API key in the settings.")

    static let keychainMigrationFailed = String(localized: "The API key could not be stored securely in the Keychain. The previous value is kept.")
    static let keychainSaveFailed = String(localized: "The API key could not be saved to the Keychain. The previous value is kept.")

    static func rewriteFailed(_ reason: String) -> String {
        String(localized: "Rewriting failed. The original dictation is ready to copy. \(reason)")
    }

    static let pasteBlockedExplanation = String(localized: """
    SPEXT copied the text to the clipboard but cannot trigger ⌘V without Accessibility access. Input Monitoring is not enough for that. Allow SPEXT in System Settings → Privacy & Security → Accessibility, or press ⌘V manually once.
    """)

    static let pasteTargetChangedExplanation = String(localized: """
    SPEXT copied the text to the clipboard but did not paste it automatically. The target window or the clipboard changed during processing, or Accessibility access is missing. Switch to the field you want and press ⌘V.
    """)

    static let hotkeysBlockedExplanation = String(localized: """
    SPEXT is not allowed to monitor global keyboard shortcuts. Allow SPEXT in System Settings → Privacy & Security → Input Monitoring. Accessibility alone is not enough for that.
    """)
}
