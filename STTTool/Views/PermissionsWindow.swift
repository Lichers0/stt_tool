import AppKit
import SwiftUI

// MARK: - Window Controller

@MainActor
final class PermissionsWindowController {
    private var window: NSWindow?

    func show(
        permissionsService: PermissionsServiceProtocol,
        keychainService: KeychainServiceProtocol,
        onComplete: @escaping () -> Void
    ) {
        guard window == nil else {
            focus()
            return
        }

        let view = PermissionsSetupView(
            permissionsService: permissionsService,
            keychainService: keychainService,
            onComplete: { [weak self] in
                self?.close()
                onComplete()
            }
        )

        let hostingView = NSHostingView(rootView: view)
        hostingView.setFrameSize(NSSize(width: 400, height: 380))

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 380),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        w.title = "STT Tool Setup"
        w.contentView = hostingView
        w.center()
        w.isReleasedWhenClosed = false
        w.level = .floating
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func focus() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    func close() {
        window?.close()
        window = nil
    }
}

// MARK: - SwiftUI View

struct PermissionsSetupView: View {
    let permissionsService: PermissionsServiceProtocol
    let keychainService: KeychainServiceProtocol
    let onComplete: () -> Void

    @State private var micGranted = false
    @State private var accessibilityGranted = false
    @State private var accessibilityWaiting = false
    @State private var keychainStatus: KeychainProbeStatus = .notConfigured

    var body: some View {
        VStack(spacing: DS.Spacing.xl) {
            // Header
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
                    description: micGranted
                        ? "Microphone access granted."
                        : "Required to record your speech.",
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
                    description: accessibilityGranted
                        ? "Accessibility access granted."
                        : "Required to paste text into other apps.",
                    granted: accessibilityGranted,
                    isWaiting: accessibilityWaiting,
                    actionLabel: "Open Settings",
                    action: {
                        permissionsService.openAccessibilitySettings()
                        permissionsService.startAccessibilityPolling()
                    }
                )

                PermissionCard(
                    index: 3,
                    icon: "key.fill",
                    title: "Keychain",
                    description: keychainDescription,
                    granted: keychainStatus == .accessible,
                    actionLabel: "Allow Access",
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
        .onAppear {
            micGranted = permissionsService.isMicrophoneGranted
            accessibilityGranted = permissionsService.isAccessibilityGranted
            accessibilityWaiting = permissionsService.isWaitingForAccessibility
            permissionsService.probeKeychainAccess(using: keychainService)
            keychainStatus = permissionsService.keychainStatus
        }
        .onChange(of: permissionsService.isAccessibilityGranted) { _, newValue in
            accessibilityGranted = newValue
        }
        .onChange(of: permissionsService.isWaitingForAccessibility) { _, newValue in
            accessibilityWaiting = newValue
        }
        .onChange(of: permissionsService.keychainStatus) { _, newValue in
            keychainStatus = newValue
        }
    }

    private var keychainDescription: String {
        switch keychainStatus {
        case .accessible: "Deepgram API key accessible."
        case .notConfigured: "Not configured yet — set up in Settings later."
        case .denied: "Access denied. Press Always Allow when prompted."
        }
    }
}
