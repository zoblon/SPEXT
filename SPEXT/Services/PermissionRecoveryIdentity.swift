import AppKit

/// Always identify the actual running bundle rather than a guessed installation path.
struct PermissionRecoveryIdentity {
    let appURL: URL
    let version: String
    let build: String

    init(bundle: Bundle = .main) {
        appURL = bundle.bundleURL
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([appURL])
    }
}
