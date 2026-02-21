import Foundation

// MARK: - Service Protocols

protocol AudioCaptureServiceProtocol: AnyObject {
    var isRecording: Bool { get }
    func startRecording() throws
    func stopRecording() -> [Float]
}

protocol TranscriptionServiceProtocol: AnyObject, Sendable {
    var isModelLoaded: Bool { get }
    var currentModelName: String { get }
    func loadModel(_ name: String) async throws
    func transcribe(samples: [Float]) async throws -> TranscriptionRecord
}

protocol TextInsertionServiceProtocol: AnyObject, Sendable {
    func insertText(_ text: String) async throws
}

protocol HotKeyServiceProtocol: AnyObject {
    var onToggle: (() -> Void)? { get set }
    func register()
    func unregister()
}

protocol HistoryServiceProtocol: AnyObject {
    var records: [TranscriptionRecord] { get }
    func add(_ record: TranscriptionRecord)
    func remove(at offsets: IndexSet)
    func clearAll()
}

@MainActor
protocol ModelManagerProtocol: AnyObject {
    var availableModels: [String] { get }
    var selectedModel: String { get set }
    var isDownloading: Bool { get }
    var downloadProgress: Double { get }
    func recommendedModel() -> String
}

@MainActor
protocol PermissionsServiceProtocol: AnyObject {
    var isMicrophoneGranted: Bool { get }
    var isAccessibilityGranted: Bool { get }
    func requestMicrophoneAccess() async -> Bool
    func openAccessibilitySettings()
    func checkPermissions()
}

protocol TextProcessingPipelineProtocol: AnyObject, Sendable {
    func process(_ text: String) async -> String
}

protocol KeychainServiceProtocol: AnyObject {
    func saveAPIKey(_ key: String) throws
    func loadAPIKey() -> String?
    func deleteAPIKey() throws
}

protocol DeepgramServiceProtocol: AnyObject {
    var onInterimResult: ((String) -> Void)? { get set }
    var onFinalResult: ((String) -> Void)? { get set }
    var onError: ((Error) -> Void)? { get set }
    var isConnected: Bool { get }
    func connect(apiKey: String, vocabulary: [String]) async throws
    func startStreaming()
    func sendAudioChunk(_ data: Data)
    func stopStreaming() async -> String
    func disconnect()
}

// MARK: - Service Container

@MainActor
final class ServiceContainer {
    let audioCaptureService: AudioCaptureServiceProtocol
    let transcriptionService: TranscriptionServiceProtocol
    let textInsertionService: TextInsertionServiceProtocol
    let hotKeyService: HotKeyServiceProtocol
    let historyService: HistoryServiceProtocol
    let modelManager: ModelManagerProtocol
    let permissionsService: PermissionsServiceProtocol
    let textProcessingPipeline: TextProcessingPipelineProtocol
    let keychainService: KeychainServiceProtocol
    let deepgramService: DeepgramServiceProtocol

    init(
        audioCaptureService: AudioCaptureServiceProtocol? = nil,
        transcriptionService: TranscriptionServiceProtocol? = nil,
        textInsertionService: TextInsertionServiceProtocol? = nil,
        hotKeyService: HotKeyServiceProtocol? = nil,
        historyService: HistoryServiceProtocol? = nil,
        modelManager: ModelManagerProtocol? = nil,
        permissionsService: PermissionsServiceProtocol? = nil,
        textProcessingPipeline: TextProcessingPipelineProtocol? = nil,
        keychainService: KeychainServiceProtocol? = nil,
        deepgramService: DeepgramServiceProtocol? = nil
    ) {
        self.audioCaptureService = audioCaptureService ?? AudioCaptureService()
        self.transcriptionService = transcriptionService ?? TranscriptionService()
        self.textInsertionService = textInsertionService ?? TextInsertionService()
        self.hotKeyService = hotKeyService ?? HotKeyService()
        self.historyService = historyService ?? HistoryService()
        self.modelManager = modelManager ?? ModelManager()
        self.permissionsService = permissionsService ?? PermissionsService()
        self.textProcessingPipeline = textProcessingPipeline ?? TextProcessingPipeline()
        self.keychainService = keychainService ?? KeychainService()
        self.deepgramService = deepgramService ?? DeepgramService()
    }
}
