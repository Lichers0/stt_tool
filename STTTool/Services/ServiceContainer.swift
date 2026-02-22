import Foundation

// MARK: - Service Protocols

protocol AudioCaptureServiceProtocol: AnyObject {
    var isRecording: Bool { get }
    func startRecording() throws
    func stopRecording() -> [Float]
    func startStreaming(onChunk: @escaping (Data) -> Void) throws
    func stopStreamingAndGetSamples() -> [Float]
    func startBuffering()
    func flushBuffer(to callback: (Data) -> Void)
    func replaceChunkCallback(_ callback: @escaping (Data) -> Void)
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
    var onModeToggle: (() -> Void)? { get set }
    var onCancel: (() -> Void)? { get set }
    func register()
    func unregister()
    func registerModeToggle()
    func unregisterModeToggle()
    func registerCancel()
    func unregisterCancel()
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

enum KeychainProbeStatus {
    case notConfigured
    case accessible
    case denied
}

@MainActor
protocol PermissionsServiceProtocol: AnyObject {
    var isMicrophoneGranted: Bool { get }
    var isAccessibilityGranted: Bool { get }
    var keychainStatus: KeychainProbeStatus { get }
    var allRequiredPermissionsGranted: Bool { get }
    func requestMicrophoneAccess() async -> Bool
    func openAccessibilitySettings()
    func checkPermissions()
    func probeKeychainAccess(using keychain: KeychainServiceProtocol)
    func startAccessibilityPolling()
    func stopAccessibilityPolling()
}

protocol TextProcessingPipelineProtocol: AnyObject, Sendable {
    func process(_ text: String) async -> String
}

protocol KeychainServiceProtocol: AnyObject {
    func saveAPIKey(_ key: String) throws
    func loadAPIKey() -> String?
    func deleteAPIKey() throws
}

protocol DeepgramRESTServiceProtocol: AnyObject, Sendable {
    func transcribe(audioData: Data, apiKey: String, vocabulary: [String]) async throws -> String
}

@MainActor
protocol VocabularyServiceProtocol: AnyObject {
    var vocabularies: [Vocabulary] { get }
    var activeVocabularyId: UUID? { get }
    var activeVocabulary: Vocabulary? { get }
    var startupMode: VocabularyStartupMode { get set }
    var defaultVocabularyId: UUID? { get set }
    func setActiveVocabulary(_ id: UUID)
    @discardableResult func createVocabulary(name: String, terms: [String]) -> Vocabulary
    func updateVocabulary(_ vocabulary: Vocabulary)
    func deleteVocabulary(_ id: UUID)
    func duplicateVocabulary(_ id: UUID)
    func reorder(fromOffsets source: IndexSet, toOffset destination: Int)
    func addTerm(_ term: String, to vocabularyId: UUID)
    func removeTerm(_ term: String, from vocabularyId: UUID)
    func removeTerms(at offsets: IndexSet, from vocabularyId: UUID)
    func copyTerms(_ terms: [String], to targetId: UUID)
    func moveTerms(_ terms: [String], from sourceId: UUID, to targetId: UUID)
    func vocabularyBySortOrder() -> [Vocabulary]
    func nextVocabulary(after currentId: UUID) -> Vocabulary?
    func previousVocabulary(before currentId: UUID) -> Vocabulary?
}

protocol DeepgramServiceProtocol: AnyObject {
    var onInterimResult: ((String) -> Void)? { get set }
    var onFinalResult: ((String) -> Void)? { get set }
    var onError: ((Error) -> Void)? { get set }
    var isConnected: Bool { get }
    func connect(apiKey: String, vocabulary: [String]) async throws
    func startStreaming(preserveAccumulatedText: Bool)
    func sendAudioChunk(_ data: Data)
    func sendFinalize()
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
    let deepgramRESTService: DeepgramRESTServiceProtocol
    let vocabularyService: VocabularyServiceProtocol

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
        deepgramService: DeepgramServiceProtocol? = nil,
        deepgramRESTService: DeepgramRESTServiceProtocol? = nil,
        vocabularyService: VocabularyServiceProtocol? = nil
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
        self.deepgramRESTService = deepgramRESTService ?? DeepgramRESTService()
        self.vocabularyService = vocabularyService ?? VocabularyService()
        VocabularyServiceShared.instance = self.vocabularyService
    }
}
