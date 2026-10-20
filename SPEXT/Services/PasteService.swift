import AppKit
import CoreGraphics
import OSLog

private let pasteLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "de.Rehkopf.SPEXT",
    category: "Paste"
)

class PasteService {
    private let clipboard = ClipboardRestoreService()

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
        pasteLogger.info("Paste begin chars=\(text.count, privacy: .public)")

        // A failed/blocked shortcut keeps a plain copy available for manual pasting.
        guard let initialTicket = clipboard.prepare(text: InsertionFitter.fit(text, context: nil)) else {
            pasteLogger.warning("Paste cancelled clipboardSnapshotUnavailable=true")
            completion(false)
            return
        }

        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as NSDictionary
        guard AXIsProcessTrustedWithOptions(opts) else {
            clipboard.keepForManualPaste(initialTicket)
            pasteLogger.warning("Paste fallback clipboardOnly=true")
            completion(false)
            return
        }

        // 80 ms delay: enough time for the target app to regain focus
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            guard let target,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier,
                  self.clipboard.owns(initialTicket) else {
                self.clipboard.keepForManualPaste(initialTicket)
                pasteLogger.warning("Paste cancelled targetOrClipboardChanged=true")
                completion(false)
                return
            }
            // Field context is read only here, locally, after transcription/rewriting.
            let snapshot = FocusedFieldReader.capture(processIdentifier: target.processIdentifier)
            let insertion = InsertionFitter.fit(text, context: snapshot?.context)
            guard self.clipboard.owns(initialTicket),
                  let ticket = self.clipboard.prepare(text: insertion) else {
                completion(false)
                return
            }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier,
                  snapshot?.isCurrent() != false,
                  self.clipboard.owns(ticket), AXIsProcessTrusted(), self.simulateCmdV() else {
                self.clipboard.keepForManualPaste(ticket)
                completion(false)
                return
            }
            self.clipboard.didTriggerPaste(ticket)
            pasteLogger.info("Paste shortcut posted; field insertion not independently confirmed")
            completion(true)
        }
    }

    // MARK: - Simulate Cmd+V via CGEvent

    private func simulateCmdV() -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)

        // Virtual key code 9 = "v"
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else { return false }
        keyDown.flags = .maskCommand

        keyUp.flags = .maskCommand

        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap:   .cgAnnotatedSessionEventTap)
        return true
    }
}
