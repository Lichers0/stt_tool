import Foundation
import SwiftUI
import Carbon.HIToolbox
import Sparkle

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var selectedModel: String
    @Published var isDownloadingModel = false
    @Published var hotKeyKeyCode: UInt32
    @Published var hotKeyModifiers: UInt32

    // Deepgram settings
    @Published var selectedEngine: String
    @Published var deepgramMode: String
    @Published var hasAPIKey: Bool
    @Published var apiKeyError: String?
    @Published var isValidatingKey = false
    @Published var modeToggleKeyCode: UInt32
    @Published var cancelKeyCode: UInt32
    @Published var soundMode: String

    // Sparkle updater
    var updater: SPUUpdater?

    let availableModels = Constants.availableModels
    let modelDescriptions = Constants.modelDescriptions

    private let services: ServiceContainer
    private let onModelChange: (String) -> Void

    init(services: ServiceContainer, onModelChange: @escaping (String) -> Void) {
        self.services = services
        self.onModelChange = onModelChange
        self.selectedModel = services.modelManager.selectedModel

        let savedKeyCode = UInt32(UserDefaults.standard.integer(forKey: Constants.hotKeyKeyCodeKey))
        let savedModifiers = UInt32(UserDefaults.standard.integer(forKey: Constants.hotKeyModifiersKey))

        if savedKeyCode != 0 {
            self.hotKeyKeyCode = savedKeyCode
            self.hotKeyModifiers = savedModifiers
        } else {
            self.hotKeyKeyCode = UInt32(kVK_Space)
            self.hotKeyModifiers = UInt32(NSEvent.ModifierFlags([.command, .shift]).rawValue)
        }

        // Deepgram
        self.selectedEngine = UserDefaults.standard.string(forKey: Constants.deepgramEngineKey) ?? Constants.defaultEngine
        self.deepgramMode = UserDefaults.standard.string(forKey: Constants.deepgramModeKey) ?? Constants.defaultDeepgramMode
        self.hasAPIKey = services.keychainService.hasAPIKey()

        let savedToggleCode = UInt32(UserDefaults.standard.integer(forKey: Constants.modeToggleKeyCodeKey))
        self.modeToggleKeyCode = savedToggleCode != 0 ? savedToggleCode : Constants.defaultModeToggleKeyCode

        let savedCancelCode = UInt32(UserDefaults.standard.integer(forKey: Constants.cancelKeyCodeKey))
        self.cancelKeyCode = savedCancelCode != 0 ? savedCancelCode : Constants.defaultCancelKeyCode

        let saved = UserDefaults.standard.string(forKey: Constants.soundModeKey) ?? "on"
        // Migrate legacy "default"/"custom" values to "on"
        self.soundMode = (saved == "off") ? "off" : "on"
    }

    func selectModel(_ model: String) {
        guard model != selectedModel else { return }
        selectedModel = model
        services.modelManager.selectedModel = model
        onModelChange(model)
    }

    // MARK: - Deepgram API Key

    func saveAPIKey(_ key: String) async {
        isValidatingKey = true
        apiKeyError = nil

        var request = URLRequest(url: URL(string: "https://api.deepgram.com/v1/projects")!)
        request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                try services.keychainService.saveAPIKey(key)
                hasAPIKey = true
            } else {
                apiKeyError = "Invalid API key"
            }
        } catch {
            apiKeyError = error.localizedDescription
        }

        isValidatingKey = false
    }

    func deleteAPIKey() {
        try? services.keychainService.deleteAPIKey()
        hasAPIKey = false
    }

    // MARK: - Engine Selection

    func setEngine(_ engine: String) {
        selectedEngine = engine
        UserDefaults.standard.set(engine, forKey: Constants.deepgramEngineKey)
    }

    func setDeepgramMode(_ mode: String) {
        deepgramMode = mode
        UserDefaults.standard.set(mode, forKey: Constants.deepgramModeKey)
    }

    // MARK: - Mode Toggle Key

    func saveModeToggleKey() {
        UserDefaults.standard.set(Int(modeToggleKeyCode), forKey: Constants.modeToggleKeyCodeKey)
    }

    var modeToggleKeyDisplayString: String {
        Self.keyDisplayName(for: modeToggleKeyCode)
    }

    // MARK: - Cancel Key

    func saveCancelKey() {
        UserDefaults.standard.set(Int(cancelKeyCode), forKey: Constants.cancelKeyCodeKey)
    }

    func resetCancelKey() {
        cancelKeyCode = Constants.defaultCancelKeyCode
        saveCancelKey()
    }

    var cancelKeyDisplayString: String {
        Self.keyDisplayName(for: cancelKeyCode)
    }

    // MARK: - Updates

    func checkForUpdates() {
        updater?.checkForUpdates()
    }

    var canCheckForUpdates: Bool {
        updater?.canCheckForUpdates ?? false
    }

    // MARK: - Sound Mode

    func setSoundMode(_ mode: String) {
        soundMode = mode
        UserDefaults.standard.set(mode, forKey: Constants.soundModeKey)
    }

    // MARK: - Hotkey Management

    var hotKeyDisplayString: String {
        var parts: [String] = []
        let mods = NSEvent.ModifierFlags(rawValue: UInt(hotKeyModifiers))

        if mods.contains(.control) { parts.append("⌃") }
        if mods.contains(.option) { parts.append("⌥") }
        if mods.contains(.shift) { parts.append("⇧") }
        if mods.contains(.command) { parts.append("⌘") }

        parts.append(Self.keyDisplayName(for: hotKeyKeyCode))

        return parts.joined(separator: " ")
    }

    func saveHotKey() {
        UserDefaults.standard.set(Int(hotKeyKeyCode), forKey: Constants.hotKeyKeyCodeKey)
        UserDefaults.standard.set(Int(hotKeyModifiers), forKey: Constants.hotKeyModifiersKey)
    }

    func resetHotKey() {
        hotKeyKeyCode = UInt32(kVK_Space)
        hotKeyModifiers = UInt32(NSEvent.ModifierFlags([.command, .shift]).rawValue)
        saveHotKey()
        services.hotKeyService.unregister()
        services.hotKeyService.register()
    }

    func suspendHotKey() {
        services.hotKeyService.unregister()
    }

    func resumeHotKey() {
        services.hotKeyService.register()
    }

    var permissionsService: PermissionsServiceProtocol {
        services.permissionsService
    }

    // MARK: - Key Display Names

    static func keyDisplayName(for keyCode: UInt32) -> String {
        let specialKeys: [UInt32: String] = [
            49: "Space", 36: "Return", 48: "Tab", 51: "Delete",
            53: "Esc", 117: "Fwd Del",
            126: "↑", 125: "↓", 123: "←", 124: "→",
            115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5",
            97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
            103: "F11", 111: "F12",
        ]
        if let name = specialKeys[keyCode] { return name }

        let letterKeys: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
            37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
            43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`",
        ]
        if let name = letterKeys[keyCode] { return name }

        return "Key \(keyCode)"
    }
}
