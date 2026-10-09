import Foundation

enum SPEXTPermission: CaseIterable, Equatable {
    case inputMonitoring
    case accessibility
    case microphone

    var title: String {
        switch self {
        case .inputMonitoring:
            return "Eingabeüberwachung"
        case .accessibility:
            return "Bedienungshilfen"
        case .microphone:
            return "Mikrofon"
        }
    }

    var detail: String {
        switch self {
        case .inputMonitoring:
            return "Erkennt die globalen Shortcuts außerhalb von SPEXT."
        case .accessibility:
            return "Fügt transkribierten Text automatisch per ⌘V ein."
        case .microphone:
            return "Nimmt deine Sprache auf."
        }
    }

    var systemImage: String {
        switch self {
        case .inputMonitoring:
            return "keyboard"
        case .accessibility:
            return "hand.raised"
        case .microphone:
            return "mic"
        }
    }
}

struct PermissionChecklist: Equatable {
    let hasInputMonitoring: Bool
    let hasAccessibility: Bool
    let hasMicrophone: Bool

    var missingPermissions: [SPEXTPermission] {
        var missing: [SPEXTPermission] = []
        if !hasInputMonitoring { missing.append(.inputMonitoring) }
        if !hasAccessibility { missing.append(.accessibility) }
        if !hasMicrophone { missing.append(.microphone) }
        return missing
    }

    var needsSetup: Bool {
        !missingPermissions.isEmpty
    }

    func isGranted(_ permission: SPEXTPermission) -> Bool {
        switch permission {
        case .inputMonitoring:
            return hasInputMonitoring
        case .accessibility:
            return hasAccessibility
        case .microphone:
            return hasMicrophone
        }
    }
}
