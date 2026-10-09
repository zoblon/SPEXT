import Cocoa
import CoreGraphics

/// Monitors a global modifier key combination via CGEventTap.
/// "Down" fires when EXACTLY the configured flags are active.
/// "Up" fires as soon as one of the keys is released.
class HotkeyManager {

    var onKeyDown: (() -> Void)?
    var onKeyUp:   (() -> Void)?

    /// The modifier combination that triggers this hotkey.
    /// e.g. [.maskAlternate, .maskControl] for ⌥⌃
    var triggerFlags: CGEventFlags

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isActive  = false
    var isInstalled: Bool { eventTap != nil }

    /// Indirection between the CGEventTap callback and HotkeyManager.
    /// The callback retains the box (passRetained); the box holds the manager only weakly.
    /// When the manager is deallocated, the callback becomes a no-op –
    /// no manual retain count management on the manager itself is needed.
    private class CallbackBox {
        weak var manager: HotkeyManager?
        init(_ manager: HotkeyManager) { self.manager = manager }
    }
    private var retainedBoxPtr: UnsafeMutableRawPointer?

    /// Generic modifier bits (without L/R distinction).
    /// Used for backward compatibility: hotkeys without device bits are
    /// only checked against these bits.
    static let generalModifiers = HotkeySettings.generalModifiers

    /// Device-specific L/R bits from IOKit/hidsystem/IOLLEvent.h.
    /// These bits are contained in CGEvent.flags, not in NSEvent.modifierFlags.
    ///
    /// 0x00000001 = Left Control   0x00002000 = Right Control
    /// 0x00000002 = Left Shift     0x00000004 = Right Shift
    /// 0x00000008 = Left Command   0x00000010 = Right Command
    /// 0x00000020 = Left Option    0x00000040 = Right Option
    static let deviceModifiersMask = HotkeySettings.deviceModifiersMask

    /// All known modifier bits: generic + device-specific (L/R).
    /// Fn, NumLock and other unknown bits are ignored.
    static let knownModifiers = HotkeySettings.knownModifiers

    // MARK: - Init / Deinit

    init(triggerFlags: CGEventFlags) {
        self.triggerFlags = triggerFlags
        setupEventTap()
    }

    deinit { teardown() }

    // MARK: - Set Up Event Tap

    func setupEventTap() {
        teardown()

        let mask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue

        // Box is retained (passRetained), the manager inside it only weakly.
        let box    = CallbackBox(self)
        let boxPtr = Unmanaged.passRetained(box).toOpaque()
        retainedBoxPtr = boxPtr

        guard let tap = CGEvent.tapCreate(
            tap:              .cgSessionEventTap,
            place:            .headInsertEventTap,
            options:          .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, ptr -> Unmanaged<CGEvent>? in
                guard let ptr else { return Unmanaged.passUnretained(event) }
                // takeUnretainedValue: the box stays retained, no additional retain needed
                let box = Unmanaged<CallbackBox>.fromOpaque(ptr).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    box.manager?.restoreEventTap()
                } else {
                    box.manager?.handleFlagsChanged(event: event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: boxPtr
        ) else {
            // Undo the box retain, since no tap was created
            Unmanaged<CallbackBox>.fromOpaque(boxPtr).release()
            retainedBoxPtr = nil
            print("⚠️ SPEXT: CGEventTap could not be created.\n"
                + "   → System Settings › Privacy & Security › Input Monitoring → enable SPEXT.")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.eventTap = tap
    }

    func teardown() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        // Release the box retain from setupEventTap()
        if let ptr = retainedBoxPtr {
            Unmanaged<CallbackBox>.fromOpaque(ptr).release()
            retainedBoxPtr = nil
        }
        isActive = false
    }

    private func restoreEventTap() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
        // A key release during the interruption must not keep the recording stuck.
        if isActive, !HotkeySettings.matches(
            current: CGEventSource.flagsState(.combinedSessionState), trigger: triggerFlags
        ) {
            isActive = false
            onKeyUp?()
        }
    }

    // MARK: - Evaluate Flags

    private func handleFlagsChanged(event: CGEvent) {
        let triggered = HotkeySettings.matches(current: event.flags, trigger: triggerFlags)

        if triggered, !isActive {
            isActive = true
            onKeyDown?()
        } else if !triggered, isActive {
            isActive = false
            onKeyUp?()
        }
    }

    // MARK: - Display Helper

    /// Readable short label for a combination, e.g. "OPT+CMD" or "ROPT+RCMD".
    /// If the flags contain L/R bits, side prefixes are shown (L/R).
    static func label(for flags: CGEventFlags) -> String {
        let hasDeviceBits = !flags.intersection(deviceModifiersMask).isEmpty
        var parts: [String] = []

        if hasDeviceBits {
            // L/R-specific display: generic bit → present, device bit → which side
            if flags.contains(.maskControl) {
                parts.append(flags.rawValue & 0x00002000 != 0 ? "RCTRL" : "LCTRL")
            }
            if flags.contains(.maskAlternate) {
                parts.append(flags.rawValue & 0x00000040 != 0 ? "ROPT" : "LOPT")
            }
            if flags.contains(.maskShift) {
                parts.append(flags.rawValue & 0x00000004 != 0 ? "RSHIFT" : "LSHIFT")
            }
            if flags.contains(.maskCommand) {
                parts.append(flags.rawValue & 0x00000010 != 0 ? "RCMD" : "LCMD")
            }
        } else {
            // Generic display (backward compatible – no side stored)
            if flags.contains(.maskControl)   { parts.append("CTRL") }
            if flags.contains(.maskAlternate) { parts.append("OPT") }
            if flags.contains(.maskShift)     { parts.append("SHIFT") }
            if flags.contains(.maskCommand)   { parts.append("CMD") }
        }

        return parts.isEmpty ? "–" : parts.joined(separator: "+")
    }

    // MARK: - Accessibility

    static func isAccessibilityGranted() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as NSDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    static func requestAccessibilityPermission() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as NSDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }
}
