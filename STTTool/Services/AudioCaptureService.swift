@preconcurrency import AVFoundation
import CoreAudio
import Foundation

final class AudioCaptureService: AudioCaptureServiceProtocol, @unchecked Sendable {
    private var audioEngine: AVAudioEngine
    private var samples: [Float] = []
    private var recordingStartTime: Date?
    private let lock = NSLock()
    private var chunkCallback: ((Data) -> Void)?
    private var isStreamingMode = false
    private var isBuffering = false
    private var audioBuffer: [Data] = []
    private let bufferLock = NSLock()
    private var drainSemaphore: DispatchSemaphore?
    private var configObserver: NSObjectProtocol?
    private var deviceChangeExpected = false
    private var expectedDeviceChangeResetTask: Task<Void, Never>?
    private var preferredInputDeviceID: AudioDeviceID?
    private var isRecoveringFromConfigChange = false
    private var hasInstalledTap = false
    private var consecutiveRecoveryCount = 0
    private var configChangeDebounceTask: Task<Void, Never>?
    private static let maxConsecutiveRecoveries = 3

    private(set) var isRecording = false
    var onDeviceDisconnected: (() -> Void)?

    init() {
        audioEngine = AVAudioEngine()
        observeConfigurationChanges()
    }

    deinit {
        expectedDeviceChangeResetTask?.cancel()
        configChangeDebounceTask?.cancel()
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func startRecording() throws {
        guard !isRecording else { return }

        consecutiveRecoveryCount = 0

        lock.lock()
        samples.removeAll()
        lock.unlock()

        removeTapIfInstalled()
        rebuildAudioEngine()

        do {
            try configureAudioEngineForStart()
            try audioEngine.start()
            print("[AudioCapture] Engine started, input format: \(audioEngine.inputNode.outputFormat(forBus: 0))")
            try installRecordingTap()
            isRecording = true
            recordingStartTime = Date()
        } catch {
            removeTapIfInstalled()
            audioEngine.stop()
            throw error
        }
    }

    private func installRecordingTap() throws {
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioCaptureError.formatError
        }

        var converter: AVAudioConverter?
        var converterFormatSignature: String?

        removeTapIfInstalled()

        let tapBlock: AVAudioNodeTapBlock = { [weak self] buffer, _ in
            guard let self else { return }
            let sourceFormat = buffer.format
            let formatSignature = self.converterFormatSignature(sourceFormat)

            if converter == nil || converterFormatSignature != formatSignature {
                guard let newConverter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
                    print("[AudioCapture] WARNING: failed to create recording converter from \(sourceFormat)")
                    return
                }
                converter = newConverter
                converterFormatSignature = formatSignature
                print("[AudioCapture] Recording source format: \(sourceFormat)")
            }
            guard let converter else { return }

            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * targetFormat.sampleRate / sourceFormat.sampleRate
            )
            guard frameCount > 0 else { return }

            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: frameCount
            ) else { return }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            guard status != .error, error == nil,
                  let channelData = convertedBuffer.floatChannelData
            else { return }

            let count = Int(convertedBuffer.frameLength)
            let newSamples = Array(UnsafeBufferPointer(start: channelData[0], count: count))

            self.lock.lock()
            self.samples.append(contentsOf: newSamples)
            self.lock.unlock()
        }

        // Use ObjC @try/@catch to catch NSException from installTap format mismatch
        var tapError: NSError?
        let success = ObjCTryCatch({
            self.audioEngine.inputNode.installTap(
                onBus: 0, bufferSize: 4096, format: nil, block: tapBlock
            )
        }, &tapError)

        guard success else {
            print("[AudioCapture] installTap failed: \(tapError?.localizedDescription ?? "unknown")")
            throw AudioCaptureError.tapInstallFailed
        }
        hasInstalledTap = true
    }

    func startStreaming(onChunk: @escaping (Data) -> Void) throws {
        guard !isRecording else {
            print("[AudioCapture] startStreaming skipped, already recording")
            return
        }
        print("[AudioCapture] startStreaming")

        consecutiveRecoveryCount = 0

        lock.lock()
        samples.removeAll()
        lock.unlock()

        chunkCallback = onChunk
        isStreamingMode = true

        removeTapIfInstalled()
        rebuildAudioEngine()

        do {
            try configureAudioEngineForStart()
            try audioEngine.start()
            print("[AudioCapture] Engine started, input format: \(audioEngine.inputNode.outputFormat(forBus: 0))")
            try installStreamingTap()
            isRecording = true
            recordingStartTime = Date()
        } catch {
            removeTapIfInstalled()
            audioEngine.stop()
            throw error
        }
    }

    private func installStreamingTap() throws {
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        ) else {
            throw AudioCaptureError.formatError
        }

        var converter: AVAudioConverter?
        var converterFormatSignature: String?

        removeTapIfInstalled()

        let tapBlock: AVAudioNodeTapBlock = { [weak self] buffer, _ in
            guard let self else { return }
            let sourceFormat = buffer.format
            let formatSignature = self.converterFormatSignature(sourceFormat)

            if converter == nil || converterFormatSignature != formatSignature {
                guard let newConverter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
                    print("[AudioCapture] WARNING: failed to create streaming converter from \(sourceFormat)")
                    return
                }
                converter = newConverter
                converterFormatSignature = formatSignature
                print("[AudioCapture] Streaming source format: \(sourceFormat)")
            }
            guard let converter else { return }

            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * targetFormat.sampleRate / sourceFormat.sampleRate
            )
            guard frameCount > 0 else { return }

            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: frameCount
            ) else { return }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            guard status != .error, error == nil else { return }

            let count = Int(convertedBuffer.frameLength)

            if let int16Data = convertedBuffer.int16ChannelData {
                let data = Data(bytes: int16Data[0], count: count * 2)

                self.bufferLock.lock()
                if self.isBuffering {
                    self.audioBuffer.append(data)
                    self.bufferLock.unlock()
                } else {
                    let callback = self.chunkCallback
                    let sem = self.drainSemaphore
                    if sem != nil { self.drainSemaphore = nil }
                    self.bufferLock.unlock()
                    callback?(data)
                    sem?.signal()
                }

                var floats = [Float](repeating: 0, count: count)
                for i in 0..<count {
                    floats[i] = Float(int16Data[0][i]) / 32768.0
                }
                self.lock.lock()
                self.samples.append(contentsOf: floats)
                self.lock.unlock()
            } else {
                print("[AudioCapture] WARNING: int16ChannelData is nil!")
            }
        }

        // Use ObjC @try/@catch to catch NSException from installTap format mismatch
        var tapError: NSError?
        let success = ObjCTryCatch({
            self.audioEngine.inputNode.installTap(
                onBus: 0, bufferSize: 4096, format: nil, block: tapBlock
            )
        }, &tapError)

        guard success else {
            print("[AudioCapture] installTap failed: \(tapError?.localizedDescription ?? "unknown")")
            throw AudioCaptureError.tapInstallFailed
        }
        hasInstalledTap = true
    }

    func stopStreamingAndGetSamples() -> [Float] {
        let samples = stopRecording()    // removeTap first — no more chunks from audio thread
        chunkCallback = nil
        isStreamingMode = false
        bufferLock.lock()
        isBuffering = false
        audioBuffer.removeAll()
        drainSemaphore = nil
        bufferLock.unlock()
        return samples
    }

    func drainLastChunkAndStopStreaming() async -> [Float] {
        guard isRecording, isStreamingMode else { return stopStreamingAndGetSamples() }

        let semaphore = DispatchSemaphore(value: 0)
        setDrainSemaphore(semaphore)

        // Wait for next audio callback (sends last chunk) or safety timeout
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                _ = semaphore.wait(timeout: .now() + 0.3)
                continuation.resume()
            }
        }

        setDrainSemaphore(nil)
        return stopStreamingAndGetSamples()
    }

    private func setDrainSemaphore(_ semaphore: DispatchSemaphore?) {
        bufferLock.lock()
        drainSemaphore = semaphore
        bufferLock.unlock()
    }

    // MARK: - Buffering

    func startBuffering() {
        bufferLock.lock()
        isBuffering = true
        audioBuffer.removeAll()
        bufferLock.unlock()
    }

    func flushBuffer(to callback: (Data) -> Void) {
        bufferLock.lock()
        let buffered = audioBuffer
        audioBuffer.removeAll()
        isBuffering = false
        bufferLock.unlock()

        for chunk in buffered {
            callback(chunk)
        }
    }

    func replaceChunkCallback(_ callback: @escaping (Data) -> Void) {
        bufferLock.lock()
        chunkCallback = callback
        bufferLock.unlock()
    }

    // MARK: - Device Selection

    func setInputDevice(_ deviceID: AudioDeviceID?) throws {
        preferredInputDeviceID = deviceID

        if isRecording {
            try switchToPreferredInputDeviceWhileRecording()
        } else {
            rebuildAudioEngine()
            printSelectedInputDevice(prefix: "[AudioCapture] Input device set")
        }
    }

    private func applyPreferredInputDevice() throws {
        guard let preferredInputDeviceID else { return }
        try applyInputDeviceToAudioUnit(preferredInputDeviceID)
    }

    private func configureAudioEngineForStart() throws {
        _ = audioEngine.inputNode
        if preferredInputDeviceID != nil {
            markExpectedDeviceChange()
        }
        try applyPreferredInputDevice()
        try prepareAudioEngine()
    }

    private func prepareAudioEngine() throws {
        var prepareError: NSError?
        let success = ObjCTryCatch({
            self.audioEngine.prepare()
        }, &prepareError)

        guard success else {
            print("[AudioCapture] prepare failed: \(prepareError?.localizedDescription ?? "unknown")")
            throw AudioCaptureError.enginePrepareFailed
        }
    }

    private func applyInputDeviceToAudioUnit(_ deviceID: AudioDeviceID) throws {
        let inputNode = audioEngine.inputNode
        guard let audioUnit = inputNode.audioUnit else {
            throw AudioCaptureError.deviceError
        }

        var devID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &devID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        guard status == noErr else {
            throw AudioCaptureError.deviceError
        }

        // Uninitialize the audio unit so the engine discards the cached format
        // from the previous (default) device. engine.prepare() will re-initialize
        // the unit and pick up the new device's actual hardware format.
        AudioUnitUninitialize(audioUnit)
    }

    /// Switch to a new input device while recording. Briefly interrupts audio capture.
    /// If not recording, sets the device for the next recording start.
    func switchDevice(_ deviceID: AudioDeviceID) throws {
        preferredInputDeviceID = deviceID

        guard isRecording else {
            rebuildAudioEngine()
            printSelectedInputDevice(prefix: "[AudioCapture] Input device set")
            return
        }

        try switchToPreferredInputDeviceWhileRecording()
    }

    private func switchToPreferredInputDeviceWhileRecording() throws {
        markExpectedDeviceChange()

        // Stop engine and remove tap
        removeTapIfInstalled()
        audioEngine.stop()
        isRecording = false  // suppress config change observer

        // Reinstall tap with new device's format and restart
        do {
            try reinstallTapAndRestart()
            isRecording = true
            printSelectedInputDevice(prefix: "[AudioCapture] Device switched successfully")
        } catch {
            resetState()
            throw error
        }
    }

    /// Reinstall audio tap with current input format and restart engine.
    private func reinstallTapAndRestart() throws {
        // If preferred device is no longer available, fall back to system default
        if let preferred = preferredInputDeviceID, !isDeviceAvailable(preferred) {
            print("[AudioCapture] Preferred device \(preferred) no longer available — using system default")
            preferredInputDeviceID = nil
        }

        do {
            try prepareStartAndInstallTap()
        } catch where preferredInputDeviceID != nil {
            // Tap or engine failed with preferred device — fall back to system default
            let failedDevice = preferredInputDeviceID!
            preferredInputDeviceID = nil
            print("[AudioCapture] Failed with device \(failedDevice) — retrying with system default")
            removeTapIfInstalled()
            audioEngine.stop()
            try prepareStartAndInstallTap()
        }
    }

    private func prepareStartAndInstallTap() throws {
        rebuildAudioEngine()
        try configureAudioEngineForStart()
        try audioEngine.start()
        let runningInputFormat = audioEngine.inputNode.outputFormat(forBus: 0)
        print("[AudioCapture] Engine restarted, input format: \(runningInputFormat)")

        do {
            if isStreamingMode {
                try installStreamingTap()
            } else {
                try installRecordingTap()
            }
        } catch {
            removeTapIfInstalled()
            audioEngine.stop()
            throw error
        }
    }

    private func markExpectedDeviceChange() {
        deviceChangeExpected = true
        expectedDeviceChangeResetTask?.cancel()
        expectedDeviceChangeResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.deviceChangeExpected = false
        }
    }

    private func printSelectedInputDevice(prefix: String) {
        if let preferredInputDeviceID {
            print("\(prefix) to ID \(preferredInputDeviceID)")
        } else {
            print("\(prefix) to system default")
        }
    }

    // MARK: - Device Disconnect Handling

    private func observeConfigurationChanges() {
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if self.isRecoveringFromConfigChange {
                print("[AudioCapture] Config change while recovery in progress — ignoring")
                return
            }
            if self.deviceChangeExpected {
                // Don't clear — let the timeout clear it. This prevents cascading
                // recoveries when multiple config changes fire during device transition.
                print("[AudioCapture] Config change after device switch — ignoring")
                return
            }
            guard self.isRecording else { return }

            // Debounce: wait for transient config changes to settle
            // (e.g. Bluetooth profile switch, multi-channel device init)
            print("[AudioCapture] Config change detected — waiting for hardware to settle")
            self.configChangeDebounceTask?.cancel()
            self.configChangeDebounceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(1000))
                guard let self, !Task.isCancelled, self.isRecording else { return }
                self.performConfigChangeRecovery()
            }
        }
    }

    private func performConfigChangeRecovery() {
        configChangeDebounceTask = nil

        consecutiveRecoveryCount += 1
        if consecutiveRecoveryCount > Self.maxConsecutiveRecoveries {
            print("[AudioCapture] Too many consecutive recoveries (\(consecutiveRecoveryCount)) — treating as device error")
            forceStop()
            onDeviceDisconnected?()
            return
        }

        print("[AudioCapture] Attempting recovery (\(consecutiveRecoveryCount)/\(Self.maxConsecutiveRecoveries))")
        isRecoveringFromConfigChange = true
        markExpectedDeviceChange()
        defer { isRecoveringFromConfigChange = false }
        removeTapIfInstalled()
        audioEngine.stop()
        isRecording = false

        do {
            try reinstallTapAndRestart()
            isRecording = true
            print("[AudioCapture] Recovery successful — recording continues")
        } catch {
            print("[AudioCapture] Recovery failed: \(error) — device disconnected")
            resetState()
            onDeviceDisconnected?()
        }
    }

    /// Check if a CoreAudio device still has input streams (i.e., is available for recording).
    private func isDeviceAvailable(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr && size > 0
    }

    private func converterFormatSignature(_ format: AVAudioFormat) -> String {
        "\(format.commonFormat.rawValue)-\(format.sampleRate)-\(format.channelCount)-\(format.isInterleaved)"
    }

    private func rebuildAudioEngine() {
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
            configObserver = nil
        }

        if hasInstalledTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }

        audioEngine.stop()
        audioEngine = AVAudioEngine()
        observeConfigurationChanges()
    }

    private func resetState() {
        isRecording = false
        hasInstalledTap = false
        consecutiveRecoveryCount = 0
        configChangeDebounceTask?.cancel()
        configChangeDebounceTask = nil
        lock.lock()
        samples.removeAll()
        lock.unlock()
        chunkCallback = nil
        isStreamingMode = false
        bufferLock.lock()
        isBuffering = false
        audioBuffer.removeAll()
        drainSemaphore = nil
        bufferLock.unlock()
    }

    private func forceStop() {
        removeTapIfInstalled()
        audioEngine.stop()
        resetState()
    }

    func stopRecording() -> [Float] {
        guard isRecording else { return [] }

        removeTapIfInstalled()
        audioEngine.stop()
        isRecording = false

        lock.lock()
        let result = samples
        samples.removeAll()
        lock.unlock()

        return result
    }

    private func removeTapIfInstalled() {
        guard hasInstalledTap else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        hasInstalledTap = false
    }
}

enum AudioCaptureError: LocalizedError {
    case formatError
    case converterError
    case deviceError
    case enginePrepareFailed
    case tapInstallFailed

    var errorDescription: String? {
        switch self {
        case .formatError:
            return "Failed to create target audio format"
        case .converterError:
            return "Failed to create audio converter"
        case .deviceError:
            return "Failed to set audio input device"
        case .enginePrepareFailed:
            return "Failed to prepare audio engine"
        case .tapInstallFailed:
            return "Failed to install audio tap (format mismatch)"
        }
    }
}
