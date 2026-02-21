import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

enum TextInsertionError: LocalizedError {
    case accessibilityNotGranted
    case eventCreationFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityNotGranted:
            return "Accessibility access required. Grant it in System Settings > Privacy & Security > Accessibility."
        case .eventCreationFailed:
            return "Failed to create keyboard event for paste simulation."
        }
    }
}

final class TextInsertionService: TextInsertionServiceProtocol, @unchecked Sendable {

    func insertText(_ text: String) async throws {
        // Accessibility is required for CGEvent.post to deliver events
        guard AXIsProcessTrusted() else {
            print("[PasteFallback] AXIsProcessTrusted = false!")
            throw TextInsertionError.accessibilityNotGranted
        }

        // Save current clipboard contents
        let pasteboard = NSPasteboard.general
        let previousContents = savePasteboard(pasteboard)
        print("[PasteFallback] Saved clipboard (\(previousContents.count) types)")

        // Put transcription text into clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        print("[PasteFallback] Text placed on clipboard, length=\(text.count)")

        // Small delay to let the pasteboard sync
        try await Task.sleep(for: .milliseconds(
            Int(Constants.appActivationDelay * 1000)
        ))

        // Simulate Cmd+V
        print("[PasteFallback] Simulating Cmd+V...")
        try simulatePaste()
        print("[PasteFallback] Cmd+V sent")

        // Wait before restoring clipboard
        try await Task.sleep(for: .milliseconds(
            Int(Constants.clipboardRestoreDelay * 1000)
        ))

        // Restore previous clipboard contents
        restorePasteboard(pasteboard, contents: previousContents)
        print("[PasteFallback] Clipboard restored")
    }

    // MARK: - Private

    private func simulatePaste() throws {
        // Use .hidSystemState to avoid inheriting modifier keys the user
        // may still be holding from the hotkey (e.g. Cmd+Shift+Space).
        let source = CGEventSource(stateID: .hidSystemState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else {
            throw TextInsertionError.eventCreationFailed
        }

        keyDown.flags = .maskCommand
        keyDown.post(tap: .cgAnnotatedSessionEventTap)

        // Small delay so the target app processes key-down before key-up.
        Thread.sleep(forTimeInterval: 0.05)

        keyUp.flags = .maskCommand
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }

    private func savePasteboard(_ pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType: Data] {
        var contents: [NSPasteboard.PasteboardType: Data] = [:]
        guard let items = pasteboard.pasteboardItems else { return contents }

        for item in items {
            for type in item.types {
                if let data = item.data(forType: type) {
                    contents[type] = data
                }
            }
        }
        return contents
    }

    private func restorePasteboard(
        _ pasteboard: NSPasteboard,
        contents: [NSPasteboard.PasteboardType: Data]
    ) {
        pasteboard.clearContents()
        if contents.isEmpty { return }

        let item = NSPasteboardItem()
        for (type, data) in contents {
            item.setData(data, forType: type)
        }
        pasteboard.writeObjects([item])
    }
}
