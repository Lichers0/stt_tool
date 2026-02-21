import AVFoundation
import Cocoa
import Foundation
import Security

@MainActor
final class PermissionsService: ObservableObject, PermissionsServiceProtocol {
    @Published private(set) var isMicrophoneGranted = false
    @Published private(set) var isAccessibilityGranted = false
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
        let result = keychain.loadAPIKey()
        if result != nil {
            keychainStatus = .accessible
            return
        }

        // loadAPIKey() returns nil for both "no key saved" and "access denied".
        // Distinguish by checking if the item exists at all.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.romodanov.STTTool",
            kSecAttrAccount as String: "deepgram-api-key",
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            keychainStatus = .notConfigured
        } else if status == errSecSuccess {
            keychainStatus = .accessible
        } else {
            keychainStatus = .denied
        }
    }

    func startAccessibilityPolling() {
        stopAccessibilityPolling()
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.isAccessibilityGranted = AXIsProcessTrusted()
            }
        }
    }

    func stopAccessibilityPolling() {
        accessibilityTimer?.invalidate()
        accessibilityTimer = nil
    }
}
