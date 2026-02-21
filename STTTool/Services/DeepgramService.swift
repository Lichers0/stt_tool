import Foundation

// MARK: - WebSocket State Machine

enum DeepgramConnectionState {
    case disconnected
    case connecting
    case ready
    case streaming
    case idle
}

final class DeepgramService: DeepgramServiceProtocol, @unchecked Sendable {

    // MARK: - Callbacks

    var onInterimResult: ((String) -> Void)?
    var onFinalResult: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    // MARK: - State

    private(set) var isConnected: Bool = false
    private var state: DeepgramConnectionState = .disconnected
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var keepAliveTimer: Timer?
    private var ttlTimer: Timer?
    private var accumulatedText = ""
    private let lock = NSLock()

    // MARK: - Connect

    func connect(apiKey: String, vocabulary: [String]) async throws {
        guard state == .disconnected else { return }
        state = .connecting

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
            queryItems.append(URLQueryItem(name: "keywords", value: "\(term):1.5"))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            state = .disconnected
            throw DeepgramError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        session = URLSession(configuration: .default)
        webSocketTask = session?.webSocketTask(with: request)
        webSocketTask?.resume()

        state = .ready
        isConnected = true
        startReceiving()
    }

    // MARK: - Streaming

    func startStreaming() {
        guard state == .ready || state == .idle else { return }

        stopTTLTimer()
        stopKeepAliveTimer()

        lock.lock()
        accumulatedText = ""
        lock.unlock()

        state = .streaming
    }

    func sendAudioChunk(_ data: Data) {
        guard state == .streaming else { return }
        let message = URLSessionWebSocketTask.Message.data(data)
        webSocketTask?.send(message) { [weak self] error in
            if let error {
                self?.handleError(error)
            }
        }
    }

    func stopStreaming() async -> String {
        guard state == .streaming else {
            return getAccumulatedText()
        }

        state = .idle
        startKeepAliveTimer()
        startTTLTimer()

        // Small delay to receive final results
        try? await Task.sleep(for: .milliseconds(500))

        return getAccumulatedText()
    }

    private func getAccumulatedText() -> String {
        lock.lock()
        let text = accumulatedText
        lock.unlock()
        return text
    }

    // MARK: - Disconnect

    func disconnect() {
        stopKeepAliveTimer()
        stopTTLTimer()

        if state == .streaming || state == .idle || state == .ready {
            let closeMessage = URLSessionWebSocketTask.Message.string("{\"type\":\"CloseStream\"}")
            webSocketTask?.send(closeMessage) { _ in }
        }

        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
        state = .disconnected
        isConnected = false
    }

    // MARK: - Receive Loop

    private func startReceiving() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                self.handleMessage(message)
                self.startReceiving()
            case .failure(let error):
                self.handleError(error)
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = message else { return }
        guard let data = text.data(using: .utf8) else { return }

        do {
            let response = try JSONDecoder().decode(DeepgramResponse.self, from: data)

            guard let alternative = response.channel?.alternatives?.first else { return }
            let transcript = alternative.transcript ?? ""

            if transcript.isEmpty { return }

            if response.isFinal == true {
                lock.lock()
                if !accumulatedText.isEmpty && !accumulatedText.hasSuffix(" ") {
                    accumulatedText += " "
                }
                accumulatedText += transcript
                lock.unlock()

                DispatchQueue.main.async {
                    self.onFinalResult?(transcript)
                }
            } else {
                DispatchQueue.main.async {
                    self.onInterimResult?(transcript)
                }
            }
        } catch {
            // Ignore non-result messages (metadata, etc.)
        }
    }

    private func handleError(_ error: Error) {
        DispatchQueue.main.async {
            self.onError?(error)
        }
        disconnect()
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
        let message = URLSessionWebSocketTask.Message.string("{\"type\":\"KeepAlive\"}")
        webSocketTask?.send(message) { _ in }
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
