import AppKit
import CoreGraphics
import OSLog

private let pasteLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "de.Rehkopf.SPEXT",
    category: "Paste"
)

class PasteService {

    struct Target: Equatable {
        let processIdentifier: pid_t
        let bundleIdentifier: String?
    }

    func captureTarget() -> Target? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return Target(
            processIdentifier: app.processIdentifier,
            bundleIdentifier: app.bundleIdentifier
        )
    }

    /// Copies the text and reports after the target check whether Cmd+V was triggered.
    func paste(text: String, target: Target?, completion: @escaping (Bool) -> Void) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        let pasteboardChangeCount = NSPasteboard.general.changeCount
        pasteLogger.info("Paste begin chars=\(text.count, privacy: .public)")

        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as NSDictionary
        guard AXIsProcessTrustedWithOptions(opts) else {
            pasteLogger.warning("Paste fallback clipboardOnly=true")
            completion(false)
            return
        }

        // 80 ms delay: enough time for the target app to regain focus
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            guard let target,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier,
                  NSPasteboard.general.changeCount == pasteboardChangeCount else {
                pasteLogger.warning("Paste cancelled targetOrClipboardChanged=true")
                completion(false)
                return
            }
            self.simulateCmdV()
            pasteLogger.info("Paste completed via simulated shortcut")
            completion(true)
        }
    }

    // MARK: - Simulate Cmd+V via CGEvent

    private func simulateCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)

        // Virtual key code 9 = "v"
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand

        let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        keyUp?.post(tap:   .cgAnnotatedSessionEventTap)
    }
}
