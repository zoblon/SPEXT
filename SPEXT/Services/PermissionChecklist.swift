import Foundation

enum SPEXTPermission: CaseIterable, Equatable {
    case inputMonitoring
    case accessibility
    case microphone

    var title: String {
        switch self {
        case .inputMonitoring:
            return String(localized: "Input Monitoring")
        case .accessibility:
            return String(localized: "Accessibility")
        case .microphone:
            return String(localized: "Microphone")
        }
    }

    var detail: String {
        switch self {
        case .inputMonitoring:
            return String(localized: "Detects the global shortcuts outside SPEXT.")
        case .accessibility:
            return String(localized: "Pastes transcribed text automatically via ⌘V.")
        case .microphone:
            return String(localized: "Records your voice.")
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
