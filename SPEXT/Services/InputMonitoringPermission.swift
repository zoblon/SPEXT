import CoreGraphics

enum InputMonitoringPermission {
    static var isGranted: Bool {
        // Match the CGEvent listen-only tap used by HotkeyManager. A System Settings
        // switch (or a grant to a different app copy) is not a grant to this process.
        CGPreflightListenEventAccess()
    }

    @discardableResult
    static func request() -> Bool {
        CGRequestListenEventAccess()
    }
}
