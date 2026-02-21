import Foundation
import WhisperKit

final class TranscriptionService: TranscriptionServiceProtocol, @unchecked Sendable {
    private var whisperKit: WhisperKit?
    private(set) var isModelLoaded = false
    private(set) var currentModelName = ""

    func loadModel(_ name: String) async throws {
        let config = WhisperKitConfig(
            model: name,
            verbose: false,
            prewarm: true
        )
        let kit = try await WhisperKit(config)
        self.whisperKit = kit
        self.currentModelName = name
        self.isModelLoaded = true
    }

    func transcribe(samples: [Float]) async throws -> TranscriptionRecord {
        guard let whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        let options = DecodingOptions(
            language: nil,
            detectLanguage: true
        )

        let results = try await whisperKit.transcribe(
            audioArray: samples,
            decodeOptions: options
        )

        guard let result = results.first else {
            throw TranscriptionError.emptyResult
        }

        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = result.language

        let durationSeconds = Double(samples.count) / 16000.0

        return TranscriptionRecord(
            text: text,
            language: language,
            modelName: currentModelName,
            durationSeconds: durationSeconds
        )
    }
}

enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Whisper model is not loaded"
        case .emptyResult:
            return "Transcription returned no results"
        }
    }
}
