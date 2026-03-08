@preconcurrency import AVFoundation
import CoreAudio
import Foundation

final class AudioCaptureService: AudioCaptureServiceProtocol, @unchecked Sendable {
    private let audioEngine = AVAudioEngine()
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

    private(set) var isRecording = false
    var onDeviceDisconnected: (() -> Void)?

    init() {
        observeConfigurationChanges()
    }

    deinit {
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func startRecording() throws {
        guard !isRecording else { return }

        lock.lock()
        samples.removeAll()
        lock.unlock()

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Target format: 16kHz, mono, float32 (what WhisperKit expects)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioCaptureError.formatError
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioCaptureError.converterError
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * 16000.0 / inputFormat.sampleRate
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

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
        recordingStartTime = Date()
    }

    func startStreaming(onChunk: @escaping (Data) -> Void) throws {
        guard !isRecording else {
            print("[AudioCapture] startStreaming skipped, already recording")
            return
        }
        print("[AudioCapture] startStreaming")

        lock.lock()
        samples.removeAll()
        lock.unlock()

        chunkCallback = onChunk
        isStreamingMode = true

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Target format: 16kHz, mono, int16 (what Deepgram expects)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        ) else {
            throw AudioCaptureError.formatError
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioCaptureError.converterError
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * 16000.0 / inputFormat.sampleRate
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

            // Send int16 chunk to callback for Deepgram (or buffer it)
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

                // Also accumulate float32 samples for fallback/duration tracking
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

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
        recordingStartTime = Date()
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
        guard let deviceID else { return }  // nil = use system default (no-op)

        // Suppress the AVAudioEngineConfigurationChange that fires
        // when we programmatically switch the input device.
        deviceChangeExpected = true

        let inputNode = audioEngine.inputNode
        guard let audioUnit = inputNode.audioUnit else {
            deviceChangeExpected = false
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
            deviceChangeExpected = false
            throw AudioCaptureError.deviceError
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
            if self.deviceChangeExpected {
                self.deviceChangeExpected = false
                print("[AudioCapture] Config change after device switch — ignoring")
                return
            }
            guard self.isRecording else { return }
            print("[AudioCapture] Engine configuration changed — device likely disconnected")
            self.forceStop()
            self.onDeviceDisconnected?()
        }
    }

    private func forceStop() {
        guard isRecording else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isRecording = false

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

    func stopRecording() -> [Float] {
        guard isRecording else { return [] }

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isRecording = false

        lock.lock()
        let result = samples
        samples.removeAll()
        lock.unlock()

        return result
    }
}

enum AudioCaptureError: LocalizedError {
    case formatError
    case converterError
    case deviceError

    var errorDescription: String? {
        switch self {
        case .formatError:
            return "Failed to create target audio format"
        case .converterError:
            return "Failed to create audio converter"
        case .deviceError:
            return "Failed to set audio input device"
        }
    }
}
