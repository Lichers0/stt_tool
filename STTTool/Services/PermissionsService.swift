import AVFoundation
import Cocoa
import Foundation

@MainActor
final class PermissionsService: ObservableObject, PermissionsServiceProtocol {
    @Published private(set) var isMicrophoneGranted = false
    @Published private(set) var isAccessibilityGranted = false

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
}
