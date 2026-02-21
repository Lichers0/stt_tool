@preconcurrency import AVFoundation
import Foundation

final class AudioCaptureService: AudioCaptureServiceProtocol {
    private let audioEngine = AVAudioEngine()
    private var samples: [Float] = []
    private var recordingStartTime: Date?
    private let lock = NSLock()

    private(set) var isRecording = false

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

    var errorDescription: String? {
        switch self {
        case .formatError:
            return "Failed to create target audio format"
        case .converterError:
            return "Failed to create audio converter"
        }
    }
}
