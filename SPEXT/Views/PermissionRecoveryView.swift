import SwiftUI

/// Shared by setup and Access settings. This guide never changes a macOS grant.
struct PermissionRecoveryView: View {
    @EnvironmentObject var appState: AppState
    @State private var expanded = false
    private let identity = PermissionRecoveryIdentity()

    var body: some View {
        DisclosureGroup("Already enabled in System Settings?", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                Text("An enabled switch can belong to another copy or an earlier build of SPEXT. The checks above show the access macOS reports for this running app.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Running copy")
                        .fontWeight(.semibold)
                    Text("Version \(identity.version) · Build \(identity.build)")
                        .foregroundStyle(.secondary)
                    Text(verbatim: identity.appURL.path)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Show this app in Finder", systemImage: "folder") {
                        identity.revealInFinder()
                    }
                    .controlSize(.small)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Keep the copy you want to use in Applications. If you move this app, quit and reopen it from Applications first.")
                    Text("2. In Input Monitoring and Accessibility, remove the SPEXT entry with −. Use + to add the running app shown here, then enable it in both sections.")
                    Text("3. Quit SPEXT completely and reopen that same copy. Then check the permissions again.")
                }
                .fixedSize(horizontal: false, vertical: true)

                ViewThatFits(in: .horizontal) {
                    HStack {
                        settingsButtons
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        settingsButtons
                    }
                }
                .controlSize(.small)
            }
            .font(.system(size: 12))
            .padding(.top, 10)
        }
        .font(.system(size: 12, weight: .medium))
    }

    @ViewBuilder
    private var settingsButtons: some View {
        Button("Input Monitoring") { appState.openPermissionSettings(.inputMonitoring) }
        Button("Accessibility") { appState.openPermissionSettings(.accessibility) }
        Button("Check again") { appState.refreshPermissionsAndHotkeys() }
    }
}
