import CoreAudio
import Foundation

/// Reads and sets the volume/mute state of the default output device.
/// Used to eliminate background noise during a recording.
struct SystemAudioController {

    enum Intervention: Equatable {
        case none
        case mute
        case volume
    }

    struct RestoreSnapshot {
        let deviceID: AudioDeviceID
        let deviceUID: String?
        let originalMute: Bool
        let originalVolume: Float
        let intervention: Intervention
        private(set) var consumed = false

        mutating func restore() -> Bool {
            guard !consumed else { return true }
            guard SystemAudioController.matchesCurrentOutput(id: deviceID, uid: deviceUID) else {
                return false
            }
            consumed = true
            switch intervention {
            case .none:
                return true
            case .mute:
                return SystemAudioController.setMute(originalMute, device: deviceID)
            case .volume:
                return SystemAudioController.setVolume(originalVolume, device: deviceID)
            }
        }
    }

    // MARK: - Public API

    /// Current volume (0.0–1.0). Returns 1.0 if it cannot be read.
    static func getVolume() -> Float {
        guard let device = defaultOutputDevice() else { return 1.0 }
        return masterVolume(device: device) ?? channelVolume(device: device, channel: 1) ?? 1.0
    }

    /// Sets the volume (0.0–1.0).
    @discardableResult
    static func setVolume(_ volume: Float) -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        return setVolume(volume, device: device)
    }

    static func captureAndSilence() -> RestoreSnapshot? {
        guard let device = defaultOutputDevice() else { return nil }
        let muted = getMute(device: device)
        let volume = masterVolume(device: device) ?? channelVolume(device: device, channel: 1) ?? 1
        let intervention: Intervention
        if muted {
            intervention = .none
        } else if setMute(true, device: device) {
            intervention = .mute
        } else if setVolume(0, device: device) {
            intervention = .volume
        } else {
            intervention = .none
        }
        return RestoreSnapshot(
            deviceID: device,
            deviceUID: deviceUID(device),
            originalMute: muted,
            originalVolume: volume,
            intervention: intervention
        )
    }

    private static func setVolume(_ volume: Float, device: AudioDeviceID) -> Bool {
        let vol = Float32(max(0, min(1, volume)))

        // Try the master element
        if setProperty(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput,
                       element: kAudioObjectPropertyElementMain, value: vol, device: device) {
            return true
        }
        // Fallback: left + right channel
        var ok = false
        for ch: AudioObjectPropertyElement in [1, 2] {
            if setProperty(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput,
                           element: ch, value: vol, device: device) { ok = true }
        }
        return ok
    }

    /// Returns whether the device is muted.
    static func getMute() -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        return getMute(device: device)
    }

    private static func getMute(device: AudioDeviceID) -> Bool {
        var muted: UInt32 = 0
        var address = address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput,
                              kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr && muted != 0
    }

    /// Sets the mute state. Returns true on success.
    @discardableResult
    static func setMute(_ mute: Bool) -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        return setMute(mute, device: device)
    }

    private static func setMute(_ mute: Bool, device: AudioDeviceID) -> Bool {
        let value: UInt32 = mute ? 1 : 0
        return setProperty(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput,
                           element: kAudioObjectPropertyElementMain, value: value, device: device)
    }

    // MARK: - Helper Methods

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice,
                          kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID
        ) == noErr else { return nil }
        return deviceID
    }

    private static func deviceUID(_ device: AudioDeviceID) -> String? {
        var addr = address(
            kAudioDevicePropertyDeviceUID,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr,
              let value else {
            return nil
        }
        return value.takeUnretainedValue() as String
    }

    private static func matchesCurrentOutput(id: AudioDeviceID, uid: String?) -> Bool {
        guard let current = defaultOutputDevice() else { return false }
        if current == id { return true }
        guard let uid else { return false }
        return deviceUID(current) == uid
    }

    private static func masterVolume(device: AudioDeviceID) -> Float? {
        var addr = address(kAudioDevicePropertyVolumeScalar,
                          kAudioDevicePropertyScopeOutput, kAudioObjectPropertyElementMain)
        var vol: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &vol) == noErr else { return nil }
        return vol
    }

    private static func channelVolume(device: AudioDeviceID, channel: AudioObjectPropertyElement) -> Float? {
        var addr = address(kAudioDevicePropertyVolumeScalar,
                          kAudioDevicePropertyScopeOutput, channel)
        var vol: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &vol) == noErr else { return nil }
        return vol
    }

    private static func address(
        _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope,
        _ element: AudioObjectPropertyElement
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    @discardableResult
    private static func setProperty<T>(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement,
        value: T,
        device: AudioDeviceID
    ) -> Bool {
        var addr = address(selector, scope, element)
        return withUnsafePointer(to: value) { ptr in
            AudioObjectSetPropertyData(
                device, &addr, 0, nil, UInt32(MemoryLayout<T>.size), ptr
            ) == noErr
        }
    }
}
