import Foundation

enum Constants {
    // MARK: - UserDefaults Keys

    static let selectedModelKey = "selectedWhisperModel"
    static let hotKeyKeyCodeKey = "hotKeyKeyCode"
    static let hotKeyModifiersKey = "hotKeyModifiers"
    static let historyKey = "transcriptionHistory"

    // MARK: - Defaults

    static let defaultModel = "base"
    static let maxHistoryRecords = 50
    static let minimumRecordingDuration: TimeInterval = 0.3
    static let clipboardRestoreDelay: TimeInterval = 0.5
    static let appActivationDelay: TimeInterval = 0.15

    // MARK: - Deepgram

    static let deepgramEngineKey = "deepgramEngine"         // "deepgram" | "whisperkit"
    static let deepgramModeKey = "deepgramMode"             // "streaming" | "rest"
    static let vocabularyTermsKey = "vocabularyTerms"       // [String]
    static let modeToggleKeyCodeKey = "modeToggleKeyCode"   // UInt32 (default: Down Arrow = 125)
    static let webSocketTTLSeconds: TimeInterval = 300      // 5 min

    static let defaultEngine = "deepgram"
    static let defaultDeepgramMode = "streaming"
    static let defaultModeToggleKeyCode: UInt32 = 125       // kVK_DownArrow

    // MARK: - Deepgram API

    static let deepgramStreamingURL = "wss://api.deepgram.com/v1/listen"
    static let deepgramRESTURL = "https://api.deepgram.com/v1/listen"
    static let deepgramModel = "nova-3"
    static let deepgramKeepAliveInterval: TimeInterval = 8

    // MARK: - Available Models

    static let availableModels = [
        "tiny",
        "base",
        "small",
        "medium",
        "large-v3",
        "large-v3_turbo"
    ]

    static let modelDescriptions: [String: String] = [
        "tiny": "Tiny (~75MB) -- fastest, lower quality",
        "base": "Base (~150MB) -- good balance",
        "small": "Small (~500MB) -- better quality",
        "medium": "Medium (~1.5GB) -- high quality",
        "large-v3": "Large V3 (~3GB) -- best quality",
        "large-v3_turbo": "Large V3 Turbo (~1.6GB) -- fast + high quality"
    ]
}
