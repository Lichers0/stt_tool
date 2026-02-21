import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class MenuBarViewModel: ObservableObject {
    // MARK: - Published State

    @Published var appState: AppState = .idle
    @Published var lastTranscription: TranscriptionRecord?
    @Published var isModelLoaded = false
    @Published var isLoadingModel = false
    @Published var modelLoadError: String?

    // MARK: - Services

    let services: ServiceContainer

    // MARK: - Private

    private var previousApp: NSRunningApplication?

    // MARK: - Init

    init(services: ServiceContainer) {
        self.services = services
        setupHotKey()
    }

    // MARK: - Public

    func toggleRecording() {
        switch appState {
        case .idle:
            startRecording()
        case .recording:
            stopRecordingAndTranscribe()
        default:
            break
        }
    }

    func loadModelAtLaunch() {
        guard !isModelLoaded, !isLoadingModel else { return }
        isLoadingModel = true
        modelLoadError = nil

        Task {
            do {
                let modelName = services.modelManager.selectedModel
                try await services.transcriptionService.loadModel(modelName)
                isModelLoaded = true
                isLoadingModel = false
            } catch {
                modelLoadError = error.localizedDescription
                isLoadingModel = false
            }
        }
    }

    func reloadModel(name: String) {
        isModelLoaded = false
        isLoadingModel = true
        modelLoadError = nil

        Task {
            do {
                try await services.transcriptionService.loadModel(name)
                isModelLoaded = true
                isLoadingModel = false
            } catch {
                modelLoadError = error.localizedDescription
                isLoadingModel = false
            }
        }
    }

    // MARK: - Private

    private func setupHotKey() {
        services.hotKeyService.onToggle = { [weak self] in
            Task { @MainActor in
                self?.toggleRecording()
            }
        }
        services.hotKeyService.register()
    }

    private func startRecording() {
        // Remember the frontmost app so we can activate it later
        previousApp = NSWorkspace.shared.frontmostApplication

        do {
            try services.audioCaptureService.startRecording()
            appState = .recording
            NSSound.tink?.play()
        } catch {
            appState = .error(error.localizedDescription)
            resetToIdleAfterDelay()
        }
    }

    private func stopRecordingAndTranscribe() {
        let samples = services.audioCaptureService.stopRecording()

        // Check minimum duration
        let durationSeconds = Double(samples.count) / 16000.0
        guard durationSeconds >= Constants.minimumRecordingDuration else {
            appState = .error("Recording too short")
            NSSound.basso?.play()
            resetToIdleAfterDelay()
            return
        }

        appState = .transcribing

        Task {
            do {
                var record = try await services.transcriptionService.transcribe(samples: samples)
                let processedText = await services.textProcessingPipeline.process(record.text)

                // Create a new record with processed text if different
                if processedText != record.text {
                    record = TranscriptionRecord(
                        text: processedText,
                        language: record.language,
                        date: record.date,
                        modelName: record.modelName,
                        durationSeconds: record.durationSeconds
                    )
                }

                services.historyService.add(record)
                lastTranscription = record

                await insertText(processedText)
            } catch {
                appState = .error(error.localizedDescription)
                NSSound.basso?.play()
                resetToIdleAfterDelay()
            }
        }
    }

    private func insertText(_ text: String) async {
        appState = .inserting

        // Activate the previous app
        if let app = previousApp {
            app.activate()
        }

        do {
            try await services.textInsertionService.insertText(text)
            appState = .idle
            NSSound.pop?.play()
        } catch {
            appState = .error(error.localizedDescription)
            resetToIdleAfterDelay()
        }
    }

    private func resetToIdleAfterDelay() {
        Task {
            try? await Task.sleep(for: .seconds(3))
            if case .error = appState {
                appState = .idle
            }
        }
    }
}

// MARK: - NSSound helpers

private extension NSSound {
    static let tink = NSSound(named: "Tink")
    static let pop = NSSound(named: "Pop")
    static let basso = NSSound(named: "Basso")
}
