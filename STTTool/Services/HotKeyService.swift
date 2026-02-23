import AppKit
import Carbon.HIToolbox
import HotKey

final class HotKeyService: HotKeyServiceProtocol {
    private var hotKey: HotKey?
    var onToggle: (() -> Void)?
    var onModeToggle: (() -> Void)?
    var onCancel: (() -> Void)?

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

        KeyInterceptor.shared.intercept(keyCode: UInt16(targetKeyCode)) { [weak self] in
            self?.onModeToggle?()
        }
    }

    func unregisterModeToggle() {
        let keyCode = UInt32(
            UserDefaults.standard.integer(forKey: Constants.modeToggleKeyCodeKey)
        )
        let targetKeyCode = keyCode != 0 ? keyCode : Constants.defaultModeToggleKeyCode
        KeyInterceptor.shared.stopIntercepting(keyCode: UInt16(targetKeyCode))
    }

    func registerCancel() {
        let keyCode = UInt32(
            UserDefaults.standard.integer(forKey: Constants.cancelKeyCodeKey)
        )
        let targetKeyCode = keyCode != 0 ? keyCode : Constants.defaultCancelKeyCode

        KeyInterceptor.shared.intercept(keyCode: UInt16(targetKeyCode)) { [weak self] in
            self?.onCancel?()
        }
    }

    func unregisterCancel() {
        let keyCode = UInt32(
            UserDefaults.standard.integer(forKey: Constants.cancelKeyCodeKey)
        )
        let targetKeyCode = keyCode != 0 ? keyCode : Constants.defaultCancelKeyCode
        KeyInterceptor.shared.stopIntercepting(keyCode: UInt16(targetKeyCode))
    }
}
