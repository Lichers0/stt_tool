import AppKit
import Carbon.HIToolbox
import HotKey

final class HotKeyService: HotKeyServiceProtocol {
    private var hotKey: HotKey?
    var onToggle: (() -> Void)?
    var onModeToggle: (() -> Void)?
    var onCancel: (() -> Void)?
    private var modeToggleMonitor: Any?
    private var cancelMonitor: Any?

    func register() {
        // Default: Cmd+Shift+Space
        let keyCode = UInt32(
            UserDefaults.standard.integer(forKey: Constants.hotKeyKeyCodeKey)
        )
        let modifiers = UInt32(
            UserDefaults.standard.integer(forKey: Constants.hotKeyModifiersKey)
        )

        let key: Key
        let mods: NSEvent.ModifierFlags

        if keyCode != 0 {
            key = Key(carbonKeyCode: keyCode) ?? .space
            mods = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        } else {
            key = .space
            mods = [.command, .shift]
        }

        hotKey = HotKey(key: key, modifiers: mods)
        hotKey?.keyDownHandler = { [weak self] in
            self?.onToggle?()
        }
    }

    func unregister() {
        hotKey = nil
    }

    func registerModeToggle() {
        let keyCode = UInt32(
            UserDefaults.standard.integer(forKey: Constants.modeToggleKeyCodeKey)
        )
        let targetKeyCode = keyCode != 0 ? keyCode : Constants.defaultModeToggleKeyCode

        modeToggleMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if UInt32(event.keyCode) == targetKeyCode {
                self?.onModeToggle?()
            }
        }
    }

    func unregisterModeToggle() {
        if let monitor = modeToggleMonitor {
            NSEvent.removeMonitor(monitor)
            modeToggleMonitor = nil
        }
    }

    func registerCancel() {
        let keyCode = UInt32(
            UserDefaults.standard.integer(forKey: Constants.cancelKeyCodeKey)
        )
        let targetKeyCode = keyCode != 0 ? keyCode : Constants.defaultCancelKeyCode

        cancelMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if UInt32(event.keyCode) == targetKeyCode {
                self?.onCancel?()
            }
        }
    }

    func unregisterCancel() {
        if let monitor = cancelMonitor {
            NSEvent.removeMonitor(monitor)
            cancelMonitor = nil
        }
    }
}
