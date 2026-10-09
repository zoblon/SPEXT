import CoreAudio
import Foundation

enum AudioDeviceTransportType: Hashable {
    case unknown
    case builtIn
    case aggregate
    case autoAggregate
    case virtual
    case pci
    case usb
    case fireWire
    case bluetooth
    case bluetoothLE
    case hdmi
    case displayPort
    case airPlay
    case avb
    case thunderbolt
    case continuityCaptureWired
    case continuityCaptureWireless
    case other(UInt32)

    init(rawValue: UInt32) {
        switch rawValue {
        case UInt32(kAudioDeviceTransportTypeBuiltIn):
            self = .builtIn
        case UInt32(kAudioDeviceTransportTypeAggregate):
            self = .aggregate
        case UInt32(kAudioDeviceTransportTypeAutoAggregate):
            self = .autoAggregate
        case UInt32(kAudioDeviceTransportTypeVirtual):
            self = .virtual
        case UInt32(kAudioDeviceTransportTypePCI):
            self = .pci
        case UInt32(kAudioDeviceTransportTypeUSB):
            self = .usb
        case UInt32(kAudioDeviceTransportTypeFireWire):
            self = .fireWire
        case UInt32(kAudioDeviceTransportTypeBluetooth):
            self = .bluetooth
        case UInt32(kAudioDeviceTransportTypeBluetoothLE):
            self = .bluetoothLE
        case UInt32(kAudioDeviceTransportTypeHDMI):
            self = .hdmi
        case UInt32(kAudioDeviceTransportTypeDisplayPort):
            self = .displayPort
        case UInt32(kAudioDeviceTransportTypeAirPlay):
            self = .airPlay
        case UInt32(kAudioDeviceTransportTypeAVB):
            self = .avb
        case UInt32(kAudioDeviceTransportTypeThunderbolt):
            self = .thunderbolt
        case UInt32(kAudioDeviceTransportTypeContinuityCaptureWired):
            self = .continuityCaptureWired
        case UInt32(kAudioDeviceTransportTypeContinuityCaptureWireless):
            self = .continuityCaptureWireless
        case 0:
            self = .unknown
        default:
            self = .other(rawValue)
        }
    }
}

struct AudioDevice: Identifiable, Hashable {
    let id: String   // UID – used to identify the device
    let name: String
    let hasInput: Bool
    let transportType: AudioDeviceTransportType

    init(
        id: String,
        name: String,
        hasInput: Bool = false,
        transportType: AudioDeviceTransportType = .unknown
    ) {
        self.id = id
        self.name = name
        self.hasInput = hasInput
        self.transportType = transportType
    }

    /// AirPods Pro, AirPods Max, AirPods (all generations)
    var isAirPods: Bool {
        name.localizedCaseInsensitiveContains("AirPods")
    }

    var isBluetooth: Bool {
        transportType == .bluetooth || transportType == .bluetoothLE || isAirPods
    }

    var isContinuityLike: Bool {
        switch transportType {
        case .continuityCaptureWired, .continuityCaptureWireless:
            return true
        default:
            return name.localizedCaseInsensitiveContains("iPhone")
                || name.localizedCaseInsensitiveContains("Continuity")
        }
    }

    /// All audio devices WITH input channels (microphones, including Bluetooth in HFP mode)
    static func inputDevices() -> [AudioDevice] {
        allAudioDevices().filter(\.hasInput)
    }

    /// Prefer AirPods automatically; otherwise the selected fallback microphone; otherwise the system default.
    static func preferredMicrophoneUID(from devices: [AudioDevice], selectedMicUID: String, preferAirPods: Bool = true) -> String? {
        if preferAirPods, let airPods = devices.first(where: \.isAirPods) {
            return airPods.id
        }
        return selectedMicUID.isEmpty ? nil : selectedMicUID
    }

    /// Only used on the recorder queue when the system default is selected.
    static func defaultInputUID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                         0, nil, &size, &id) == noErr, id != 0 else { return nil }
        return stringProperty(id, kAudioDevicePropertyDeviceUID)
    }

    /// All audio devices (input AND output) – needed for AirPods detection,
    /// since AirPods in A2DP mode (music) do not have input streams yet.
    static func allAudioDevices() -> [AudioDevice] {
        var result: [AudioDevice] = []

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize
        ) == noErr, dataSize > 0 else { return result }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids   = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &ids
        ) == noErr else { return result }

        for deviceID in ids {
            guard
                let name = stringProperty(deviceID, kAudioObjectPropertyName),
                let uid  = stringProperty(deviceID, kAudioDevicePropertyDeviceUID)
            else { continue }
            result.append(AudioDevice(
                id: uid,
                name: name,
                hasInput: hasInputStreams(deviceID),
                transportType: transportType(deviceID)
            ))
        }
        return result
    }

    /// Resolves a UID to a CoreAudio DeviceID (nil if not found)
    static func coreAudioID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        var cfUID:    CFString    = uid as CFString
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &deviceID) { ptr in
            withUnsafePointer(to: &cfUID) { uidPtr in
                AudioObjectGetPropertyData(
                    AudioObjectID(kAudioObjectSystemObject),
                    &address,
                    UInt32(MemoryLayout<CFString>.size),
                    uidPtr,
                    &size,
                    ptr
                )
            }
        }
        return (status == noErr && deviceID != 0) ? deviceID : nil
    }

    // MARK: - Helper for CFString Properties

    private static func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var inputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope:    kAudioDevicePropertyScopeInput,
            mElement:  kAudioObjectPropertyElementMain
        )
        var inputSize: UInt32 = 0
        return AudioObjectGetPropertyDataSize(deviceID, &inputAddress, 0, nil, &inputSize) == noErr
            && inputSize > 0
    }

    private static func transportType(_ deviceID: AudioDeviceID) -> AudioDeviceTransportType {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &value)
        guard status == noErr else { return .unknown }
        return AudioDeviceTransportType(rawValue: value)
    }

    private static func stringProperty(_ deviceID: AudioDeviceID,
                                       _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        var value: CFString = "" as CFString
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, $0)
        }
        guard status == noErr else { return nil }
        return value as String
    }
}
