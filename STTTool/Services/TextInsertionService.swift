import AppKit
import Carbon.HIToolbox
import Foundation

final class TextInsertionService: TextInsertionServiceProtocol, @unchecked Sendable {

    func insertText(_ text: String) async throws {
        // Save current clipboard contents
        let pasteboard = NSPasteboard.general
        let previousContents = savePasteboard(pasteboard)

        // Put transcription text into clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Small delay to let the target app become active
        try await Task.sleep(for: .milliseconds(
            Int(Constants.appActivationDelay * 1000)
        ))

        // Simulate Cmd+V
        simulatePaste()

        // Wait before restoring clipboard
        try await Task.sleep(for: .milliseconds(
            Int(Constants.clipboardRestoreDelay * 1000)
        ))

        // Restore previous clipboard contents
        restorePasteboard(pasteboard, contents: previousContents)
    }

    // MARK: - Private

    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
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
