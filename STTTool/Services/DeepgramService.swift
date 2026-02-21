import Foundation
import Starscream

// MARK: - WebSocket State Machine

enum DeepgramConnectionState {
    case disconnected
    case connecting
    case ready
    case streaming
    case idle
}

final class DeepgramService: DeepgramServiceProtocol, WebSocketDelegate, @unchecked Sendable {

    // MARK: - Callbacks

    var onInterimResult: ((String) -> Void)?
    var onFinalResult: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    // MARK: - State

    private(set) var isConnected: Bool = false
    private var state: DeepgramConnectionState = .disconnected
    private var socket: WebSocket?
    private var keepAliveTimer: Timer?
    private var ttlTimer: Timer?
    private var accumulatedText = ""
    private var latestInterimText = ""
    private let lock = NSLock()
    private var chunkCount = 0
    private var connectContinuation: CheckedContinuation<Void, any Error>?

    // MARK: - Connect

    func connect(apiKey: String, vocabulary: [String]) async throws {
        guard state == .disconnected else {
            print("[Deepgram] connect skipped, state=\(state)")
            return
        }
        state = .connecting
        print("[Deepgram] connecting...")

        var components = URLComponents(string: Constants.deepgramStreamingURL)!
        var queryItems = [
            URLQueryItem(name: "model", value: Constants.deepgramModel),
            URLQueryItem(name: "language", value: "multi"),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "endpointing", value: "100"),
            URLQueryItem(name: "interim_results", value: "true"),
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "channels", value: "1"),
        ]

        for term in vocabulary.prefix(100) {
            queryItems.append(URLQueryItem(name: "keyterm", value: term))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            state = .disconnected
            throw DeepgramError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        let socket = WebSocket(request: request)
        socket.delegate = self
        self.socket = socket

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            self.connectContinuation = continuation
            socket.connect()
        }
    }

    // MARK: - Streaming

    func startStreaming() {
        guard state == .ready || state == .idle else {
            print("[Deepgram] startStreaming skipped, state=\(state)")
            return
        }
        print("[Deepgram] startStreaming")

        stopTTLTimer()
        stopKeepAliveTimer()

        lock.lock()
        accumulatedText = ""
        latestInterimText = ""
        lock.unlock()

        chunkCount = 0
        state = .streaming
    }

    func sendAudioChunk(_ data: Data) {
        guard state == .streaming else { return }
        chunkCount += 1
        if chunkCount <= 3 || chunkCount % 50 == 0 {
            print("[Deepgram] sendAudioChunk #\(chunkCount): \(data.count) bytes")
        }
        socket?.write(data: data)
    }

    func stopStreaming() async -> String {
        guard state == .streaming else {
            print("[Deepgram] stopStreaming skipped, state=\(state)")
            return getResultText(includeInterimFallback: true)
        }

        print("[Deepgram] stopStreaming, chunks sent: \(chunkCount)")
        chunkCount = 0
        state = .idle

        // Ask Deepgram to flush pending interim tokens into final segments.
        socket?.write(string: "{\"type\":\"Finalize\"}")

        // Wait briefly for finalization messages, then fall back to interim if needed.
        try? await Task.sleep(for: .milliseconds(900))

        startKeepAliveTimer()
        startTTLTimer()

        let result = getResultText(includeInterimFallback: true)
        print("[Deepgram] stopStreaming result: \"\(result)\"")
        return result
    }

    private func getResultText(includeInterimFallback: Bool) -> String {
        lock.lock()
        let finalText = accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let interimText = latestInterimText.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.unlock()

        guard includeInterimFallback, !interimText.isEmpty else {
            return finalText
        }

        guard !finalText.isEmpty else {
            return interimText
        }

        if finalText.hasSuffix(interimText) {
            return finalText
        }

        return finalText + " " + interimText
    }

    // MARK: - Disconnect

    func disconnect() {
        stopKeepAliveTimer()
        stopTTLTimer()

        if state == .streaming || state == .idle || state == .ready {
            socket?.write(string: "{\"type\":\"CloseStream\"}")
        }

        socket?.disconnect()
        socket = nil
        state = .disconnected
        isConnected = false
        lock.lock()
        latestInterimText = ""
        lock.unlock()
    }

    // MARK: - WebSocketDelegate

    func didReceive(event: WebSocketEvent, client: any WebSocketClient) {
        switch event {
        case .connected:
            print("[Deepgram] WebSocket connected")
            state = .ready
            isConnected = true
            connectContinuation?.resume()
            connectContinuation = nil

        case .disconnected(let reason, let code):
            print("[Deepgram] WebSocket disconnected: \(reason) (code: \(code))")
            state = .disconnected
            isConnected = false

        case .text(let text):
            handleMessage(text)

        case .binary:
            print("[Deepgram] received binary message (unexpected)")

        case .error(let error):
            print("[Deepgram] WebSocket error: \(String(describing: error))")
            state = .disconnected
            isConnected = false
            if let continuation = connectContinuation {
                connectContinuation = nil
                continuation.resume(throwing: error ?? DeepgramError.serverError("Connection failed"))
            } else {
                DispatchQueue.main.async {
                    self.onError?(error ?? DeepgramError.serverError("Connection error"))
                }
            }

        case .cancelled:
            print("[Deepgram] WebSocket cancelled")
            state = .disconnected
            isConnected = false

        case .viabilityChanged(let viable):
            print("[Deepgram] viability changed: \(viable)")

        case .reconnectSuggested(let suggested):
            print("[Deepgram] reconnect suggested: \(suggested)")

        case .peerClosed:
            print("[Deepgram] peer closed")
            state = .disconnected
            isConnected = false

        case .pong:
            break
        case .ping:
            break
        }
    }

    // MARK: - Message Handling

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let msgType = json?["type"] as? String ?? "unknown"

            // Detect Deepgram error responses
            if msgType == "Error" {
                let errMsg = json?["message"] as? String
                    ?? json?["err_msg"] as? String
                    ?? text
                print("[Deepgram] ERROR from server: \(errMsg)")
                let error = DeepgramError.serverError(errMsg)
                DispatchQueue.main.async {
                    self.onError?(error)
                }
                return
            }

            let response = try JSONDecoder().decode(DeepgramResponse.self, from: data)

            guard let alternative = response.channel?.alternatives?.first else {
                if msgType != "Metadata" {
                    print("[Deepgram] message type=\(msgType), no alternatives")
                }
                return
            }
            let transcript = alternative.transcript ?? ""

            if transcript.isEmpty { return }

            if response.isFinal == true {
                print("[Deepgram] FINAL: \"\(transcript)\"")
                lock.lock()
                if !accumulatedText.isEmpty && !accumulatedText.hasSuffix(" ") {
                    accumulatedText += " "
                }
                accumulatedText += transcript
                latestInterimText = ""
                lock.unlock()

                DispatchQueue.main.async {
                    self.onFinalResult?(transcript)
                }
            } else {
                print("[Deepgram] interim: \"\(transcript)\"")
                lock.lock()
                latestInterimText = transcript
                lock.unlock()
                DispatchQueue.main.async {
                    self.onInterimResult?(transcript)
                }
            }
        } catch {
            print("[Deepgram] failed to parse message: \(text.prefix(200))")
        }
    }

    // MARK: - KeepAlive

    private func startKeepAliveTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.keepAliveTimer = Timer.scheduledTimer(
                withTimeInterval: Constants.deepgramKeepAliveInterval,
                repeats: true
            ) { [weak self] _ in
                self?.sendKeepAlive()
            }
        }
    }

    private func stopKeepAliveTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.keepAliveTimer?.invalidate()
            self?.keepAliveTimer = nil
        }
    }

    private func sendKeepAlive() {
        socket?.write(string: "{\"type\":\"KeepAlive\"}")
    }

    // MARK: - TTL Timer

    private func startTTLTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.ttlTimer = Timer.scheduledTimer(
                withTimeInterval: Constants.webSocketTTLSeconds,
                repeats: false
            ) { [weak self] _ in
                self?.disconnect()
            }
        }
    }

    private func stopTTLTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.ttlTimer?.invalidate()
            self?.ttlTimer = nil
        }
    }
}

// MARK: - Deepgram Response Models

struct DeepgramResponse: Decodable {
    let type: String?
    let channel: DeepgramChannel?
    let isFinal: Bool?
    let speechFinal: Bool?

    enum CodingKeys: String, CodingKey {
        case type
        case channel
        case isFinal = "is_final"
        case speechFinal = "speech_final"
    }
}

struct DeepgramChannel: Decodable {
    let alternatives: [DeepgramAlternative]?
}

struct DeepgramAlternative: Decodable {
    let transcript: String?
    let confidence: Double?
}

// MARK: - Errors

enum DeepgramError: LocalizedError {
    case invalidURL
    case notConnected
    case invalidAPIKey
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Deepgram API URL"
        case .notConnected:
            return "Not connected to Deepgram"
        case .invalidAPIKey:
            return "Invalid Deepgram API key"
        case .serverError(let message):
            return "Deepgram error: \(message)"
        }
    }
}
