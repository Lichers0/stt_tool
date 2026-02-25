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

        // Concrete type needed for @ObservedObject in SwiftUI
        guard let concreteService = permissionsService as? PermissionsService else { return }

        let view = PermissionsSetupView(
            permissionsService: concreteService,
            keychainService: keychainService,
            onComplete: { [weak self] in
                self?.close()
                onComplete()
            }
        )

        let hostingView = NSHostingView(rootView: view)
        hostingView.setFrameSize(NSSize(width: 400, height: 480))

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 480),
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
    @ObservedObject var permissionsService: PermissionsService
    let keychainService: KeychainServiceProtocol
    let onComplete: () -> Void

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
                    description: permissionsService.isMicrophoneGranted
                        ? "Microphone access granted."
                        : "Required to record your speech.",
                    granted: permissionsService.isMicrophoneGranted,
                    actionLabel: "Grant Access",
                    action: {
                        Task { _ = await permissionsService.requestMicrophoneAccess() }
                    }
                )

                PermissionCard(
                    index: 2,
                    icon: "accessibility",
                    title: "Accessibility",
                    description: permissionsService.isAccessibilityGranted
                        ? "Accessibility access granted."
                        : "Required to paste text into other apps.",
                    granted: permissionsService.isAccessibilityGranted,
                    isWaiting: permissionsService.isWaitingForAccessibility,
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
                    granted: permissionsService.keychainStatus == .accessible,
                    actionLabel: "Check Access",
                    action: permissionsService.keychainStatus != .accessible ? {
                        permissionsService.probeKeychainAccess(using: keychainService)
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
            .disabled(!permissionsService.isMicrophoneGranted || !permissionsService.isAccessibilityGranted)
            .opacity(!permissionsService.isMicrophoneGranted || !permissionsService.isAccessibilityGranted ? 0.5 : 1.0)
        }
        .padding(DS.Spacing.xxl)
    }

    private var keychainDescription: String {
        switch permissionsService.keychainStatus {
        case .accessible: "Deepgram API key accessible."
        case .notConfigured: "Not configured yet — set up in Settings later."
        case .denied: "Access denied. Press Always Allow when prompted."
        }
    }
}
