import AppKit
import ApplicationServices
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
    @Published var isContinueMode = false
    @Published var currentEngine: String = UserDefaults.standard.string(forKey: Constants.deepgramEngineKey) ?? Constants.defaultEngine

    // MARK: - Services

    let services: ServiceContainer

    // MARK: - Private

    private var previousApp: NSRunningApplication?
    private var previousFocusedElement: AXUIElement?
    private var previousSelectedTextRange: AXValue?
    private let overlay = FloatingOverlayWindow()
    private var recordingTimer: Timer?
    private var recordingSeconds = 0

    // Vocabulary switching
    private var previewedVocabularyId: UUID?

    // MARK: - Init

    init(services: ServiceContainer) {
        self.services = services
    }

    // MARK: - Public

    /// Call after all permissions are granted to register hotkey and prepare the app.
    func activate() {
        KeyInterceptor.shared.start()
        setupHotKey()
    }

    func toggleRecording() {
        switch appState {
        case .idle:
            startRecording()
        case .recording, .streamingRecording:
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

    // MARK: - HotKey Setup

    private func setupHotKey() {
        services.hotKeyService.onToggle = { [weak self] in
            Task { @MainActor in
                self?.toggleRecording()
            }
        }
        services.hotKeyService.onModeToggle = { [weak self] in
            Task { @MainActor in
                self?.toggleMode()
            }
        }
        services.hotKeyService.onCancel = { [weak self] in
            Task { @MainActor in
                self?.cancelRecording()
            }
        }
        services.hotKeyService.register()
    }

    private func toggleMode() {
        guard appState == .recording || appState == .streamingRecording else { return }
        isContinueMode.toggle()
        overlay.setMode(isContinueMode)
    }

    private func cancelRecording() {
        guard appState == .recording || appState == .streamingRecording else { return }

        stopRecordingTimer()
        unregisterOverlayHotkeys()
        services.hotKeyService.unregisterModeToggle()
        services.hotKeyService.unregisterCancel()

        if appState == .streamingRecording {
            _ = services.audioCaptureService.stopStreamingAndGetSamples()
            let mode = UserDefaults.standard.string(forKey: Constants.deepgramModeKey) ?? Constants.defaultDeepgramMode
            if mode == "streaming" {
                nonisolated(unsafe) let deepgram = services.deepgramService
                deepgram.disconnect()
            }
        } else {
            _ = services.audioCaptureService.stopRecording()
        }

        overlay.dismissImmediately()
        appState = .idle
        NSSound.basso?.play()
        print("[Cancel] Recording cancelled by user")
    }

    // MARK: - Start Recording

    private func startRecording() {
        guard services.permissionsService.isMicrophoneGranted,
              services.permissionsService.isAccessibilityGranted else {
            appState = .error("Permissions required. Restart the app.")
            NSSound.basso?.play()
            resetToIdleAfterDelay()
            return
        }

        previousApp = NSWorkspace.shared.frontmostApplication
        captureFocusedInputContext()
        isContinueMode = false

        let apiKey = services.keychainService.loadAPIKey()
        let useDeepgram = currentEngine == "deepgram" && apiKey != nil

        if useDeepgram {
            startDeepgramRecording(apiKey: apiKey!)
        } else {
            startWhisperKitRecording()
        }
    }

    // MARK: - WhisperKit Flow

    private func startWhisperKitRecording() {
        do {
            try services.audioCaptureService.startRecording()
            appState = .recording
            services.hotKeyService.registerCancel()
            playStartSound()
        } catch {
            appState = .error(error.localizedDescription)
            resetToIdleAfterDelay()
        }
    }

    private func stopWhisperKitRecording() {
        let samples = services.audioCaptureService.stopRecording()

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

    // MARK: - Deepgram Flow

    private func startDeepgramRecording(apiKey: String) {
        let mode = UserDefaults.standard.string(forKey: Constants.deepgramModeKey) ?? Constants.defaultDeepgramMode
        let vocabulary = services.vocabularyService.activeVocabulary?.terms ?? []

        overlay.showForRecording(targetApp: previousApp)
        overlay.setVocabularyName(services.vocabularyService.activeVocabulary?.name ?? "")
        previewedVocabularyId = nil
        overlay.setPreviewedVocabularyName(nil, isPendingSwitch: false)
        startRecordingTimer()
        registerOverlayHotkeys()

        if mode == "streaming" {
            startDeepgramStreaming(apiKey: apiKey, vocabulary: vocabulary)
        } else {
            startDeepgramREST(apiKey: apiKey, vocabulary: vocabulary)
        }
    }

    private func startDeepgramStreaming(apiKey: String, vocabulary: [String]) {
        nonisolated(unsafe) let deepgram = services.deepgramService

        deepgram.onInterimResult = { [weak self] text in
            self?.overlay.updateInterimText(text)
        }

        deepgram.onFinalResult = { [weak self] text in
            self?.overlay.updateFinalSegment(text)
        }

        deepgram.onError = { [weak self] error in
            Task { @MainActor in
                self?.appState = .error(error.localizedDescription)
                self?.overlay.dismissImmediately()
                self?.stopRecordingTimer()
                self?.services.hotKeyService.unregisterModeToggle()
                self?.services.hotKeyService.unregisterCancel()
                self?.resetToIdleAfterDelay()
            }
        }

        Task {
            do {
                if !deepgram.isConnected {
                    try await deepgram.connect(apiKey: apiKey, vocabulary: vocabulary)
                }
                deepgram.startStreaming(preserveAccumulatedText: false)

                try services.audioCaptureService.startStreaming { [weak deepgram] chunk in
                    deepgram?.sendAudioChunk(chunk)
                }

                appState = .streamingRecording
                services.hotKeyService.registerModeToggle()
                services.hotKeyService.registerCancel()
                playStartSound()
            } catch {
                appState = .error(error.localizedDescription)
                overlay.dismissImmediately()
                stopRecordingTimer()
                resetToIdleAfterDelay()
            }
        }
    }

    private func startDeepgramREST(apiKey: String, vocabulary: [String]) {
        do {
            try services.audioCaptureService.startStreaming { _ in
                // REST mode: ignore chunks, just record audio
            }
            appState = .streamingRecording
            services.hotKeyService.registerModeToggle()
            services.hotKeyService.registerCancel()
            playStartSound()
        } catch {
            appState = .error(error.localizedDescription)
            overlay.dismissImmediately()
            stopRecordingTimer()
            resetToIdleAfterDelay()
        }
    }

    // MARK: - Stop Recording

    private func stopRecordingAndTranscribe() {
        stopRecordingTimer()
        unregisterOverlayHotkeys()
        services.hotKeyService.unregisterModeToggle()
        services.hotKeyService.unregisterCancel()

        if appState == .streamingRecording {
            let mode = UserDefaults.standard.string(forKey: Constants.deepgramModeKey) ?? Constants.defaultDeepgramMode
            if mode == "streaming" {
                stopDeepgramStreaming()
            } else {
                stopDeepgramREST()
            }
        } else {
            stopWhisperKitRecording()
        }
    }

    private func stopDeepgramStreaming() {
        let samples = services.audioCaptureService.stopStreamingAndGetSamples()
        let durationSeconds = Double(samples.count) / 16000.0

        guard durationSeconds >= Constants.minimumRecordingDuration else {
            appState = .error("Recording too short")
            overlay.dismissImmediately()
            NSSound.basso?.play()
            resetToIdleAfterDelay()
            return
        }

        appState = .transcribing

        nonisolated(unsafe) let deepgram = services.deepgramService
        Task {
            var text = await deepgram.stopStreaming()
            text = await services.textProcessingPipeline.process(text)

            if isContinueMode {
                if let first = text.first, first.isUppercase {
                    text = " " + first.lowercased() + text.dropFirst()
                }
            }

            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                appState = .error("Empty transcription")
                overlay.dismissImmediately()
                NSSound.basso?.play()
                resetToIdleAfterDelay()
                return
            }

            let record = TranscriptionRecord(
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                language: "multi",
                modelName: "deepgram-\(Constants.deepgramModel)",
                durationSeconds: durationSeconds
            )
            services.historyService.add(record)
            lastTranscription = record

            await insertText(text)
        }
    }

    private func stopDeepgramREST() {
        let samples = services.audioCaptureService.stopStreamingAndGetSamples()
        let durationSeconds = Double(samples.count) / 16000.0

        guard durationSeconds >= Constants.minimumRecordingDuration else {
            appState = .error("Recording too short")
            overlay.dismissImmediately()
            NSSound.basso?.play()
            resetToIdleAfterDelay()
            return
        }

        appState = .transcribing

        // Convert float32 samples to int16 PCM data for REST API
        let int16Data = samplesToInt16Data(samples)

        let apiKey = services.keychainService.loadAPIKey() ?? ""
        let vocabulary = services.vocabularyService.activeVocabulary?.terms ?? []

        Task {
            do {
                var text = try await services.deepgramRESTService.transcribe(
                    audioData: int16Data,
                    apiKey: apiKey,
                    vocabulary: vocabulary
                )
                text = await services.textProcessingPipeline.process(text)

                if isContinueMode {
                    if let first = text.first, first.isUppercase {
                        text = " " + first.lowercased() + text.dropFirst()
                    }
                }

                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    appState = .error("Empty transcription")
                    overlay.dismissImmediately()
                    NSSound.basso?.play()
                    resetToIdleAfterDelay()
                    return
                }

                let record = TranscriptionRecord(
                    text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    language: "multi",
                    modelName: "deepgram-\(Constants.deepgramModel)-rest",
                    durationSeconds: durationSeconds
                )
                services.historyService.add(record)
                lastTranscription = record

                await insertText(text)
            } catch {
                appState = .error(error.localizedDescription)
                overlay.dismissImmediately()
                NSSound.basso?.play()
                resetToIdleAfterDelay()
            }
        }
    }

    // MARK: - Text Insertion

    private func insertText(_ text: String) async {
        appState = .inserting
        print("[InsertText] === START === text=\(text.prefix(80))...")

        // Dismiss overlay completely before activating target app --
        // a floating NSPanel can interfere with app activation on macOS 15+
        overlay.dismissImmediately()
        print("[InsertText] Overlay dismissed")

        if let app = previousApp {
            print("[InsertText] Activating app: \(app.localizedName ?? "?") (pid=\(app.processIdentifier))")
            let activated = app.activate()
            print("[InsertText] activate() returned: \(activated)")
            await waitForAppActivation(app)
            let frontmost = NSWorkspace.shared.frontmostApplication
            print("[InsertText] After wait, frontmost: \(frontmost?.localizedName ?? "nil") (pid=\(frontmost?.processIdentifier ?? -1))")
            restoreFocusedInputContext()
            print("[InsertText] Focus restored, element=\(previousFocusedElement != nil), range=\(previousSelectedTextRange != nil)")
            // Ensure hotkey key-up is processed before simulated paste.
            try? await Task.sleep(for: .milliseconds(150))
        } else {
            print("[InsertText] WARNING: previousApp is nil!")
        }

        // Try direct Accessibility text insertion first (most reliable).
        if let element = previousFocusedElement,
           insertViaAccessibility(text, into: element) {
            appState = .idle
            playStopSound()
            print("[InsertText] === DONE via Accessibility ===")
            return
        }

        // Fallback: clipboard + simulated Cmd+V paste.
        print("[InsertText] Trying fallback: clipboard + Cmd+V")
        do {
            try await services.textInsertionService.insertText(text)
            appState = .idle
            playStopSound()
            print("[InsertText] === DONE via clipboard paste ===")
        } catch {
            print("[InsertText] ERROR: \(error.localizedDescription)")
            appState = .error(error.localizedDescription)
            resetToIdleAfterDelay()
        }
    }

    private func insertViaAccessibility(_ text: String, into element: AXUIElement) -> Bool {
        guard AXIsProcessTrusted() else { return false }

        // Read the value before insertion to compare later.
        var valueBefore: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueBefore)
        let beforeStr = valueBefore as? String

        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )

        guard result == .success else {
            print("[TextInsertion] AX set failed (\(result.rawValue)), falling back to paste")
            return false
        }

        // Verify: read the value after insertion and check the text actually appeared.
        // Terminal emulators (Ghostty, iTerm2, etc.) report success but don't insert.
        var valueAfter: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueAfter)
        let afterStr = valueAfter as? String

        if let after = afterStr {
            if after != (beforeStr ?? "") && after.contains(text) {
                print("[TextInsertion] Verified via AX API")
                return true
            }
            print("[TextInsertion] AX reported success but text not found in element, falling back to paste")
            return false
        }

        // Cannot read value attribute -- trust the AX result.
        print("[TextInsertion] Cannot verify (no value attribute), trusting AX result")
        return true
    }

    // MARK: - Vocabulary Switching

    private func registerOverlayHotkeys() {
        // Left Arrow — previous vocabulary
        KeyInterceptor.shared.intercept(keyCode: 123) { [weak self] in
            Task { @MainActor in
                guard self?.appState == .streamingRecording else { return }
                self?.cycleVocabulary(forward: false)
            }
        }
        // Right Arrow — next vocabulary
        KeyInterceptor.shared.intercept(keyCode: 124) { [weak self] in
            Task { @MainActor in
                guard self?.appState == .streamingRecording else { return }
                self?.cycleVocabulary(forward: true)
            }
        }
        // Return — confirm vocabulary switch
        KeyInterceptor.shared.intercept(keyCode: 36) { [weak self] in
            Task { @MainActor in
                guard self?.appState == .streamingRecording else { return }
                self?.confirmVocabularySwitch()
            }
        }
    }

    private func unregisterOverlayHotkeys() {
        KeyInterceptor.shared.stopIntercepting(keyCode: 123)
        KeyInterceptor.shared.stopIntercepting(keyCode: 124)
        KeyInterceptor.shared.stopIntercepting(keyCode: 36)
    }

    private func cycleVocabulary(forward: Bool) {
        let vocabService = services.vocabularyService
        let currentId = previewedVocabularyId ?? vocabService.activeVocabularyId ?? vocabService.vocabularyBySortOrder().first?.id

        guard let id = currentId else { return }

        let next = forward
            ? vocabService.nextVocabulary(after: id)
            : vocabService.previousVocabulary(before: id)

        guard let nextVocab = next else { return }

        previewedVocabularyId = nextVocab.id
        let isPending = nextVocab.id != vocabService.activeVocabularyId
        overlay.setPreviewedVocabularyName(nextVocab.name, isPendingSwitch: isPending)
    }

    private func confirmVocabularySwitch() {
        guard let previewedId = previewedVocabularyId,
              previewedId != services.vocabularyService.activeVocabularyId else {
            return
        }

        let vocabService = services.vocabularyService
        guard let newVocab = vocabService.vocabularies.first(where: { $0.id == previewedId }) else { return }

        let mode = UserDefaults.standard.string(forKey: Constants.deepgramModeKey) ?? Constants.defaultDeepgramMode
        guard mode == "streaming" else { return }

        guard let apiKey = services.keychainService.loadAPIKey() else { return }

        overlay.setReconnecting(true)
        overlay.setPreviewedVocabularyName(nil, isPendingSwitch: false)

        // Step 1: Start buffering audio
        services.audioCaptureService.startBuffering()

        nonisolated(unsafe) let deepgram = services.deepgramService

        Task {
            // Step 2: Finalize current connection and wait for remaining segments
            deepgram.sendFinalize()
            try? await Task.sleep(for: .milliseconds(500))

            // Step 3: Disconnect
            deepgram.disconnect()

            // Step 4: Connect with new vocabulary
            do {
                try await deepgram.connect(apiKey: apiKey, vocabulary: newVocab.terms)
                deepgram.startStreaming(preserveAccumulatedText: true)

                // Step 5: Flush buffered audio and resume direct sending
                services.audioCaptureService.flushBuffer { [weak deepgram] chunk in
                    deepgram?.sendAudioChunk(chunk)
                }
                services.audioCaptureService.replaceChunkCallback { [weak deepgram] chunk in
                    deepgram?.sendAudioChunk(chunk)
                }

                // Update state
                vocabService.setActiveVocabulary(previewedId)
                previewedVocabularyId = nil
                overlay.setVocabularyName(newVocab.name)
                overlay.setReconnecting(false)
            } catch {
                // On failure: stop recording entirely and show error
                services.audioCaptureService.flushBuffer { _ in }
                overlay.setReconnecting(false)
                appState = .error("Vocabulary switch failed: \(error.localizedDescription)")
                overlay.dismissImmediately()
                stopRecordingTimer()
                unregisterOverlayHotkeys()
                services.hotKeyService.unregisterModeToggle()
                services.hotKeyService.unregisterCancel()
                _ = services.audioCaptureService.stopStreamingAndGetSamples()
                resetToIdleAfterDelay()
                print("[VocabSwitch] Reconnection failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Recording Timer

    private func startRecordingTimer() {
        recordingSeconds = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recordingSeconds += 1
                self?.overlay.updateTimer(self?.recordingSeconds ?? 0)
            }
        }
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    // MARK: - Helpers

    private func resetToIdleAfterDelay() {
        Task {
            try? await Task.sleep(for: .seconds(3))
            if case .error = appState {
                appState = .idle
            }
        }
    }

    private var soundMode: String {
        UserDefaults.standard.string(forKey: Constants.soundModeKey) ?? "default"
    }

    private func playStartSound() {
        switch soundMode {
        case "custom": NSSound.recordStart?.play()
        case "off":    break
        default:       NSSound.tink?.play()
        }
    }

    private func playStopSound() {
        switch soundMode {
        case "custom": NSSound.recordStop?.play()
        case "off":    break
        default:       NSSound.pop?.play()
        }
    }

    private func samplesToInt16Data(_ samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            var int16Value = Int16(clamped * 32767.0)
            data.append(Data(bytes: &int16Value, count: 2))
        }
        return data
    }

    private func captureFocusedInputContext() {
        previousFocusedElement = nil
        previousSelectedTextRange = nil

        guard AXIsProcessTrusted() else {
            print("[Capture] AXIsProcessTrusted = false!")
            return
        }
        guard let app = previousApp else {
            print("[Capture] previousApp is nil")
            return
        }

        print("[Capture] Capturing context for app: \(app.localizedName ?? "?") (pid=\(app.processIdentifier))")

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focused: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )

        guard focusResult == .success, let focusedElement = focused else {
            print("[Capture] Failed to get focused element: \(focusResult.rawValue)")
            return
        }
        let element = unsafeBitCast(focusedElement, to: AXUIElement.self)
        previousFocusedElement = element

        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        print("[Capture] Focused element role: \(role as? String ?? "unknown")")

        var selectedRange: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRange
        )

        if rangeResult == .success, let range = selectedRange {
            previousSelectedTextRange = unsafeBitCast(range, to: AXValue.self)
            print("[Capture] Selected text range captured")
        } else {
            print("[Capture] No selected text range: \(rangeResult.rawValue)")
        }
    }

    private func restoreFocusedInputContext() {
        guard AXIsProcessTrusted() else { return }
        guard let app = previousApp, let focusedElement = previousFocusedElement else { return }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        _ = AXUIElementSetAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            focusedElement
        )
        _ = AXUIElementSetAttributeValue(
            focusedElement,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )

        if let selectedTextRange = previousSelectedTextRange {
            _ = AXUIElementSetAttributeValue(
                focusedElement,
                kAXSelectedTextRangeAttribute as CFString,
                selectedTextRange
            )
        }
    }

    private func waitForAppActivation(_ app: NSRunningApplication) async {
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                return
            }
            try? await Task.sleep(for: .milliseconds(40))
        }
    }
}

// MARK: - NSSound helpers

private extension NSSound {
    static let tink = NSSound(named: "Tink")
    static let pop = NSSound(named: "Pop")
    static let basso = NSSound(named: "Basso")

    static let recordStart: NSSound? = {
        guard let url = Bundle.main.url(forResource: "button-dry-single-voiced-sharp", withExtension: "mp3") else { return nil }
        return NSSound(contentsOf: url, byReference: true)
    }()

    static let recordStop: NSSound? = {
        guard let url = Bundle.main.url(forResource: "mixkit-software-interface-start-2574", withExtension: "wav") else { return nil }
        return NSSound(contentsOf: url, byReference: true)
    }()
}
