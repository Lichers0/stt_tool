import SwiftUI

struct StartupGuardianView: View {
    let permissionsService: PermissionsServiceProtocol
    let keychainService: KeychainServiceProtocol
    let onComplete: () -> Void

    @State private var micGranted = false
    @State private var accessibilityGranted = false
    @State private var keychainStatus: KeychainProbeStatus = .notConfigured

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.and.signal.meter")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("STT Tool Setup")
                .font(.title2)
                .fontWeight(.bold)

            Text("Grant permissions to enable voice transcription.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                // Step 1: Microphone
                permissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    description: "Required to record your speech.",
                    granted: micGranted,
                    actionLabel: "Grant Access",
                    action: {
                        Task {
                            micGranted = await permissionsService.requestMicrophoneAccess()
                        }
                    }
                )

                // Step 2: Accessibility
                VStack(spacing: 4) {
                    permissionRow(
                        icon: "accessibility",
                        title: "Accessibility",
                        description: "Required to paste text into other apps.",
                        granted: accessibilityGranted,
                        actionLabel: "Open Settings",
                        action: {
                            permissionsService.openAccessibilitySettings()
                        }
                    )
                    if !accessibilityGranted {
                        Text("Enable STTTool in the list, then return here.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 44)
                    }
                }

                // Step 3: Keychain
                keychainRow()
            }

            Button("Continue") {
                permissionsService.stopAccessibilityPolling()
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .disabled(!micGranted || !accessibilityGranted)
        }
        .padding(24)
        .frame(width: 360)
        .onAppear {
            micGranted = permissionsService.isMicrophoneGranted
            accessibilityGranted = permissionsService.isAccessibilityGranted
            permissionsService.startAccessibilityPolling()
            permissionsService.probeKeychainAccess(using: keychainService)
            keychainStatus = permissionsService.keychainStatus
        }
        .onDisappear {
            permissionsService.stopAccessibilityPolling()
        }
        .onChange(of: permissionsService.isAccessibilityGranted) { _, newValue in
            accessibilityGranted = newValue
        }
        .onChange(of: permissionsService.keychainStatus) { _, newValue in
            keychainStatus = newValue
        }
    }

    // MARK: - Keychain Row

    @ViewBuilder
    private func keychainRow() -> some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill")
                .font(.title3)
                .frame(width: 32)
                .foregroundStyle(keychainStatusColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Keychain")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(keychainDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            switch keychainStatus {
            case .accessible:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .notConfigured:
                Text("--")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .denied:
                Button("Retry") {
                    permissionsService.probeKeychainAccess(using: keychainService)
                    keychainStatus = permissionsService.keychainStatus
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var keychainStatusColor: Color {
        switch keychainStatus {
        case .accessible: .green
        case .notConfigured: .secondary
        case .denied: .red
        }
    }

    private var keychainDescription: String {
        switch keychainStatus {
        case .accessible:
            "Deepgram API key accessible."
        case .notConfigured:
            "Not configured -- set up in Settings later."
        case .denied:
            "Access denied. Press Always Allow when prompted."
        }
    }

    // MARK: - Generic Permission Row

    private func permissionRow(
        icon: String,
        title: String,
        description: String,
        granted: Bool,
        actionLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 32)
                .foregroundStyle(granted ? .green : .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button(actionLabel, action: action)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
