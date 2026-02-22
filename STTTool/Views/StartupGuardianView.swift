import SwiftUI

struct StartupGuardianView: View {
    let permissionsService: PermissionsServiceProtocol
    let keychainService: KeychainServiceProtocol
    let onComplete: () -> Void

    @State private var micGranted = false
    @State private var accessibilityGranted = false
    @State private var keychainStatus: KeychainProbeStatus = .notConfigured

    var body: some View {
        VStack(spacing: DS.Spacing.xl) {
            // Icon + title
            VStack(spacing: DS.Spacing.sm) {
                RoundedRectangle(cornerRadius: DS.Spacing.lg)
                    .fill(DS.Colors.primarySubtle)
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "mic.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(DS.Colors.primary)
                    )
                Text("STT Tool Setup")
                    .font(.system(size: 15, weight: .semibold))
                Text("Grant permissions to enable voice transcription.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Permission cards
            VStack(spacing: DS.Spacing.md) {
                PermissionCard(
                    index: 1,
                    icon: "mic.fill",
                    title: "Microphone",
                    description: "Required to record your speech.",
                    granted: micGranted,
                    actionLabel: "Grant Access",
                    action: {
                        Task { micGranted = await permissionsService.requestMicrophoneAccess() }
                    }
                )

                PermissionCard(
                    index: 2,
                    icon: "accessibility",
                    title: "Accessibility",
                    description: "Required to paste text into other apps.",
                    granted: accessibilityGranted,
                    actionLabel: "Open Settings",
                    action: { permissionsService.openAccessibilitySettings() }
                )
                if !accessibilityGranted {
                    Text("Enable STTTool in the list, then return here.")
                        .font(DS.Typography.tinyLabel)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 36)
                }

                PermissionCard(
                    index: 3,
                    icon: "key.fill",
                    title: "Keychain",
                    description: keychainDescription,
                    granted: keychainStatus == .accessible,
                    actionLabel: "Retry",
                    action: keychainStatus == .denied ? {
                        permissionsService.probeKeychainAccess(using: keychainService)
                        keychainStatus = permissionsService.keychainStatus
                    } : nil
                )
            }

            // Continue button
            Button {
                permissionsService.stopAccessibilityPolling()
                onComplete()
            } label: {
                HStack(spacing: DS.Spacing.sm) {
                    Text("Continue")
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12))
                }
                .frame(maxWidth: .infinity)
                .frame(height: DS.Layout.recordButtonHeight)
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.xl)
                        .fill(DS.Colors.primary)
                )
            }
            .buttonStyle(.plain)
            .disabled(!micGranted || !accessibilityGranted)
            .opacity(!micGranted || !accessibilityGranted ? 0.5 : 1.0)
        }
        .padding(DS.Spacing.xxl)
        .frame(width: DS.Layout.popoverWidth)
        .onAppear {
            micGranted = permissionsService.isMicrophoneGranted
            accessibilityGranted = permissionsService.isAccessibilityGranted
            permissionsService.startAccessibilityPolling()
            permissionsService.probeKeychainAccess(using: keychainService)
            keychainStatus = permissionsService.keychainStatus
        }
        .onDisappear { permissionsService.stopAccessibilityPolling() }
        .onChange(of: permissionsService.isAccessibilityGranted) { _, newValue in
            accessibilityGranted = newValue
        }
        .onChange(of: permissionsService.keychainStatus) { _, newValue in
            keychainStatus = newValue
        }
    }

    private var keychainDescription: String {
        switch keychainStatus {
        case .accessible: "Deepgram API key accessible."
        case .notConfigured: "Not configured — set up in Settings later."
        case .denied: "Access denied. Press Always Allow when prompted."
        }
    }
}
