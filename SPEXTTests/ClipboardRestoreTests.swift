import AppKit
import Foundation

enum ClipboardRestoreTests {
    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        guard value() else { fputs("FAIL: Clipboard: \(message)\n", stderr); exit(1) }
    }

    static func run() {
        let board = NSPasteboard(name: .init("SPEXT.Tests.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        var time: TimeInterval = 0
        let service = ClipboardRestoreService(pasteboard: board, now: { time }, automaticallyPoll: false)
        let rich = NSPasteboardItem()
        rich.setString("Original link", forType: .string)
        let rtf = Data("{\\rtf1 Original link}".utf8)
        rich.setData(rtf, forType: .rtf)
        let file = NSPasteboardItem()
        file.setString("file:///tmp/example.txt", forType: .fileURL)
        board.clearContents(); board.writeObjects([rich, file])
        let first = service.prepare(text: "Dictated text")!
        expect(service.owns(first), "new ticket owns its pasteboard")
        service.didTriggerPaste(first)
        expect(board.string(forType: .string) == "Dictated text", "provider supplies dictated text")
        time = 0.9; service.poll()
        expect(service.owns(first), "minimum hold protects slower readers")
        time = 1.1; service.poll()
        expect(board.pasteboardItems?.count == 2, "restore all original clipboard items")
        expect(board.pasteboardItems?.first?.data(forType: .rtf) == rtf, "restore rich representation")
        expect(board.pasteboardItems?.last?.string(forType: .fileURL) == "file:///tmp/example.txt", "restore file URL")
        expect(board.string(forType: .string) == "Original link", "restore original string")

        time = 10
        let changed = service.prepare(text: "Automatic")!
        service.didTriggerPaste(changed)
        board.clearContents(); board.setString("User copied something else", forType: .string)
        time = 30; service.poll()
        expect(board.string(forType: .string) == "User copied something else", "newer copy always wins")
        expect(!service.owns(changed), "superseded ticket loses ownership")

        time = 40
        let blocked = service.prepare(text: "Manual fallback")!
        service.keepForManualPaste(blocked)
        time = 60; service.poll()
        expect(board.string(forType: .string) == "Manual fallback", "blocked paste remains available")

        time = 70
        board.clearContents(); board.setString("Before consecutive dictations", forType: .string)
        let one = service.prepare(text: "One")!; service.didTriggerPaste(one)
        let two = service.prepare(text: "Two")!; service.didTriggerPaste(two)
        expect(!service.owns(one) && service.owns(two), "old cleanup cannot own next dictation")
        expect(board.string(forType: .string) == "Two", "second dictation is delivered")
        time = 71.1; service.poll()
        expect(board.string(forType: .string) == "Before consecutive dictations", "carry original snapshot across owned sessions")

        time = 80
        board.clearContents()
        let empty = service.prepare(text: "Temporary")!; service.didTriggerPaste(empty)
        time = 84.9; service.poll()
        expect(service.owns(empty), "unread text remains during bounded wait")
        time = 85.1; service.poll()
        expect(board.pasteboardItems?.isEmpty != false, "restore empty clipboard after unread timeout")

        time = 86
        board.clearContents(); board.setString("Before slow reader", forType: .string)
        let slow = service.prepare(text: "Slow reader text")!; service.didTriggerPaste(slow)
        time = 90.9
        expect(board.string(forType: .string) == "Slow reader text", "late data request still receives transcript")
        time = 91.1; service.poll()
        expect(service.owns(slow), "quiet interval follows late read, not only the initial timeout")
        time = 91.5; service.poll()
        expect(board.string(forType: .string) == "Before slow reader", "restore after late reader quiets")

        time = 90
        board.clearContents(); board.setString("Before quit", forType: .string)
        let quit = service.prepare(text: "After shortcut")!; service.didTriggerPaste(quit)
        service.finishOnQuit()
        expect(board.string(forType: .string) == "Before quit", "quit restores owned automatic paste snapshot")
        let manual = service.prepare(text: "Keep manual on quit")!
        service.keepForManualPaste(manual); service.finishOnQuit()
        expect(board.string(forType: .string) == "Keep manual on quit", "quit preserves materialized manual fallback")
        print("PASS: Clipboard multi-item restore, ownership, timing, consecutive sessions and quit")
    }
}
