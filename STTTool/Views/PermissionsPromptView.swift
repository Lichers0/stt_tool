import SwiftUI

struct PermissionsPromptView: View {
    let permissionsService: PermissionsServiceProtocol
    let onComplete: () -> Void

    @State private var micGranted = false
    @State private var accessibilityGranted = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.and.signal.meter")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("STT Tool Setup")
                .font(.title2)
                .fontWeight(.bold)

            Text("Grant the following permissions to enable voice transcription.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                permissionCard(
                    icon: "mic.fill",
                    title: "Microphone",
                    description: "Required to record your speech.",
                    granted: micGranted,
                    action: {
                        Task {
                            micGranted = await permissionsService.requestMicrophoneAccess()
                        }
                    }
                )

                permissionCard(
                    icon: "accessibility",
                    title: "Accessibility",
                    description: "Required to paste text into other apps. Opens System Settings.",
                    granted: accessibilityGranted,
                    action: {
                        permissionsService.openAccessibilitySettings()
                    }
                )
            }

            HStack {
                Button("Refresh Status") {
                    permissionsService.checkPermissions()
                    micGranted = permissionsService.isMicrophoneGranted
                    accessibilityGranted = permissionsService.isAccessibilityGranted
                }
                .controlSize(.small)

                Spacer()

                Button("Continue") {
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!micGranted)
            }
        }
        .padding(24)
        .frame(width: 360)
        .onAppear {
            micGranted = permissionsService.isMicrophoneGranted
            accessibilityGranted = permissionsService.isAccessibilityGranted
        }
    }

    private func permissionCard(
        icon: String,
        title: String,
        description: String,
        granted: Bool,
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
                Button("Grant", action: action)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
