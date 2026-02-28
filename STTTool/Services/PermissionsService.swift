import AVFoundation
import Cocoa
import Foundation
import Security

@MainActor
final class PermissionsService: ObservableObject, PermissionsServiceProtocol {
    @Published private(set) var isMicrophoneGranted = false
    @Published private(set) var isAccessibilityGranted = false
    @Published private(set) var isWaitingForAccessibility = false
    @Published private(set) var keychainStatus: KeychainProbeStatus = .notConfigured

    var allRequiredPermissionsGranted: Bool {
        isMicrophoneGranted && isAccessibilityGranted
    }

    private var accessibilityTimer: Timer?

    init() {
        checkPermissions()
    }

    func requestMicrophoneAccess() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        isMicrophoneGranted = granted
        return granted
    }

    func openAccessibilitySettings() {
        // Prompt system to register the app, then open Accessibility settings
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )!
        NSWorkspace.shared.open(url)
    }

    func checkPermissions() {
        // Microphone
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            isMicrophoneGranted = true
        default:
            isMicrophoneGranted = false
        }

        // Accessibility
        isAccessibilityGranted = AXIsProcessTrusted()
    }

    func probeKeychainAccess(using keychain: KeychainServiceProtocol) {
        // Attempt to read the actual key data — this may trigger the system
        // "wants to use your confidential information" dialog. The user should
        // press "Always Allow" so subsequent loadAPIKey() calls won't prompt.
        if keychain.loadAPIKey() != nil {
            keychainStatus = .accessible
            return
        }

        // loadAPIKey() returned nil — distinguish "no key" from "access denied"
        // using a lightweight existence check (no data access, no dialog).
        if keychain.hasAPIKey() {
            keychainStatus = .denied
        } else {
            keychainStatus = .notConfigured
        }
    }

    func startAccessibilityPolling() {
        stopAccessibilityPolling()
        isWaitingForAccessibility = true
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let granted = AXIsProcessTrusted()
                self.isAccessibilityGranted = granted
                if granted {
                    self.stopAccessibilityPolling()
                }
            }
        }
    }

    func stopAccessibilityPolling() {
        accessibilityTimer?.invalidate()
        accessibilityTimer = nil
        isWaitingForAccessibility = false
    }
}
