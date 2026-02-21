import AppKit
import Carbon.HIToolbox
import HotKey

final class HotKeyService: HotKeyServiceProtocol {
    private var hotKey: HotKey?
    var onToggle: (() -> Void)?

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
}
