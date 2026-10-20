import SwiftUI

struct PermissionSetupView: View {
    @EnvironmentObject var appState: AppState
    let onClose: () -> Void

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Set up SPEXT")
                    .font(.system(size: 30, weight: .regular, design: .serif))

                Text("SPEXT needs these permissions so shortcuts, recording and automatic pasting work.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                ForEach(SPEXTPermission.allCases, id: \.self) { permission in
                    PermissionSetupRow(
                        permission: permission,
                        isGranted: appState.permissionChecklist.isGranted(permission)
                    ) {
                        appState.requestPermission(permission)
                    }
                    if permission != SPEXTPermission.allCases.last {
                        Divider().padding(.horizontal, 18)
                    }
                }
            }
            .background(SPEXTTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(SPEXTTheme.rule, lineWidth: 0.5))

            PermissionRecoveryView()

            Text("macOS requires your confirmation. SPEXT can request the entries and guide you to the right place, but cannot enable them without your approval.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Later") { onClose() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Check again") {
                    appState.refreshPermissionsAndHotkeys()
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
        .padding(30)
        }
        .frame(width: 580, height: 540)
        .background(SPEXTTheme.canvas)
        .tint(SPEXTTheme.accent)
        .onAppear { appState.refreshPermissionsAndHotkeys() }
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
            Image(systemName: permission.systemImage)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 34)

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
        .padding(18)
    }
}
