import SwiftUI

struct PermissionSetupView: View {
    @EnvironmentObject var appState: AppState
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Set up SPEXT")
                    .font(.system(size: 22, weight: .semibold))

                Text("SPEXT needs these permissions so shortcuts, recording and automatic pasting work.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                ForEach(SPEXTPermission.allCases, id: \.self) { permission in
                    PermissionSetupRow(
                        permission: permission,
                        isGranted: appState.permissionChecklist.isGranted(permission)
                    ) {
                        appState.requestPermission(permission)
                    }
                }
            }

            Text("macOS requires your confirmation. SPEXT can request the entries and guide you to the right place, but cannot enable them without your approval.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Later") { onClose() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Check again") {
                    appState.checkPermissions()
                    appState.setupHotkeys()
                    if !appState.permissionChecklist.needsSetup {
                        onClose()
                    }
                }

                Button("Request entries") {
                    appState.requestMissingPermissions()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!appState.permissionChecklist.needsSetup)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear { appState.checkPermissions() }
        .onChange(of: appState.permissionChecklist) { _, checklist in
            if !checklist.needsSetup {
                onClose()
            }
        }
    }
}

private struct PermissionSetupRow: View {
    let permission: SPEXTPermission
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7)
                .fill(isGranted ? Color.green.opacity(0.12) : Color(.controlBackgroundColor))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: permission.systemImage)
                        .foregroundStyle(isGranted ? .green : .secondary)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(permission.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if isGranted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            } else {
                Button("Request") { action() }
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(isGranted ? Color.green.opacity(0.05) : Color(.controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isGranted ? Color.green.opacity(0.25) : Color(.separatorColor).opacity(0.5),
                    lineWidth: 0.5
                )
        )
    }
}
