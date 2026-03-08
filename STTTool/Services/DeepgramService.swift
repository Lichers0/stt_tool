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
    private var finalizeContinuation: CheckedContinuation<Void, Never>?

    // MARK: - Word Tracking

    private var interimHistory: [[DeepgramWord]] = []
    private var bestInterim: [DeepgramWord] = []
    private var silentChunkCount = 0
    private var hasSentVADFinalize = false

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
            URLQueryItem(name: "endpointing", value: "false"),
            URLQueryItem(name: "interim_results", value: "true"),
            URLQueryItem(name: "words", value: "true"),
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

    func startStreaming(preserveAccumulatedText: Bool = false) {
        guard state == .ready || state == .idle else {
            print("[Deepgram] startStreaming skipped, state=\(state)")
            return
        }
        print("[Deepgram] startStreaming (preserveText=\(preserveAccumulatedText))")

        stopTTLTimer()
        stopKeepAliveTimer()

        lock.lock()
        if !preserveAccumulatedText {
            accumulatedText = ""
        }
        latestInterimText = ""
        lock.unlock()

        chunkCount = 0
        interimHistory = []
        bestInterim = []
        silentChunkCount = 0
        hasSentVADFinalize = false
        state = .streaming
    }

    func sendAudioChunk(_ data: Data) {
        guard state == .streaming else { return }
        chunkCount += 1
        if chunkCount <= 3 || chunkCount % 50 == 0 {
            print("[Deepgram] sendAudioChunk #\(chunkCount): \(data.count) bytes")
        }

        // VAD: detect silence and auto-finalize
        let rms = calculateRMS(data)
        if rms < Constants.silenceRMSThreshold {
            silentChunkCount += 1
            if silentChunkCount >= Constants.silentChunksForFinalize
                && !hasSentVADFinalize && !interimHistory.isEmpty {
                print("[Deepgram] VAD: \(silentChunkCount) silent chunks (\(silentChunkCount * 100)ms), sending Finalize")
                sendFinalize()
                hasSentVADFinalize = true
            }
        } else {
            silentChunkCount = 0
            hasSentVADFinalize = false
        }

        socket?.write(data: data)
    }

    func sendFinalize() {
        socket?.write(string: "{\"type\":\"Finalize\"}")
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

        // Wait for speech_final from Deepgram, with a safety timeout.
        await waitForFinalize(timeout: 3.0)

        startKeepAliveTimer()
        startTTLTimer()

        let result = getResultText(includeInterimFallback: true)
        print("[Deepgram] stopStreaming result: \"\(result)\"")
        return result
    }

    private func waitForFinalize(timeout: TimeInterval) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    self.lock.lock()
                    self.finalizeContinuation = continuation
                    self.lock.unlock()
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
            }
            // Return as soon as EITHER completes (speech_final received OR timeout)
            _ = await group.next()
            group.cancelAll()
            // Clean up continuation if timeout won
            let pending = self.consumeFinalizeContinuation()
            pending?.resume()
        }
    }

    /// Thread-safe extraction of finalizeContinuation (synchronous, safe to call from async context).
    private func consumeFinalizeContinuation() -> CheckedContinuation<Void, Never>? {
        lock.lock()
        let c = finalizeContinuation
        finalizeContinuation = nil
        lock.unlock()
        return c
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

    // MARK: - Cancel Streaming (keep connection alive)

    func cancelStreaming() {
        guard state == .streaming else { return }
        print("[Deepgram] cancelStreaming, keeping connection alive")
        chunkCount = 0
        state = .idle

        // Flush server-side buffer
        socket?.write(string: "{\"type\":\"Finalize\"}")

        startKeepAliveTimer()
        startTTLTimer()

        // Discard accumulated text and tracking
        interimHistory = []
        bestInterim = []
        lock.lock()
        accumulatedText = ""
        latestInterimText = ""
        lock.unlock()
    }

    // MARK: - Accumulated Text Manipulation

    /// Insert external text (e.g. clipboard paste) into the accumulated transcript.
    func insertAccumulatedText(_ text: String) {
        lock.lock()
        if !accumulatedText.isEmpty && !accumulatedText.hasSuffix(" ") {
            accumulatedText += " "
        }
        accumulatedText += text
        lock.unlock()
    }

    /// Remove a previously inserted text from the end of accumulated transcript.
    func removeAccumulatedText(_ text: String) {
        lock.lock()
        if accumulatedText.hasSuffix(text) {
            accumulatedText.removeLast(text.count)
        }
        lock.unlock()
    }

    /// Replace accumulated text entirely (for sync from overlay after mutations).
    func replaceAccumulatedText(_ text: String) {
        lock.lock()
        accumulatedText = text
        lock.unlock()
    }

    // MARK: - Disconnect

    func disconnect() {
        // Clean up any pending finalize wait
        consumeFinalizeContinuation()?.resume()

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
            consumeFinalizeContinuation()?.resume()

        case .text(let text):
            handleMessage(text)

        case .binary:
            print("[Deepgram] received binary message (unexpected)")

        case .error(let error):
            print("[Deepgram] WebSocket error: \(String(describing: error))")
            state = .disconnected
            isConnected = false
            consumeFinalizeContinuation()?.resume()
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
            consumeFinalizeContinuation()?.resume()

        case .viabilityChanged(let viable):
            print("[Deepgram] viability changed: \(viable)")

        case .reconnectSuggested(let suggested):
            print("[Deepgram] reconnect suggested: \(suggested)")

        case .peerClosed:
            print("[Deepgram] peer closed")
            state = .disconnected
            isConnected = false
            consumeFinalizeContinuation()?.resume()

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

            // Check speech_final before skipping empty transcripts (e.g. Finalize response after a pause)
            if response.isFinal == true && response.speechFinal == true {
                print("[Deepgram] speech_final received, resuming finalize")
                consumeFinalizeContinuation()?.resume()
            }

            if transcript.isEmpty {
                // FINAL is empty but we have tracked words — recover from bestInterim
                if response.isFinal == true && !bestInterim.isEmpty {
                    let recovered = bestInterim.map { $0.word }.joined(separator: " ")
                    print("[Deepgram] FINAL empty, recovering from bestInterim: \"\(recovered)\"")

                    interimHistory = []
                    bestInterim = []

                    lock.lock()
                    if !accumulatedText.isEmpty && !accumulatedText.hasSuffix(" ") {
                        accumulatedText += " "
                    }
                    accumulatedText += recovered
                    latestInterimText = ""
                    lock.unlock()

                    DispatchQueue.main.async {
                        self.onFinalResult?(recovered)
                    }
                }
                return
            }

            if response.isFinal == true {
                logWords("FINAL", transcript: transcript, words: alternative.words)

                // Run FINAL through tracking rules before patching
                if let finalWords = alternative.words, !finalWords.isEmpty {
                    interimHistory.append(finalWords)
                    updateBestInterim()
                    logInterimState()
                }

                // Patch FINAL with bestInterim if words were lost
                let resultTranscript: String
                if let finalWords = alternative.words, !finalWords.isEmpty, !bestInterim.isEmpty {
                    resultTranscript = patchFinalWithBestInterim(
                        finalWords: finalWords, finalTranscript: transcript
                    )
                } else {
                    resultTranscript = transcript
                }

                // Clear tracking for next segment
                interimHistory = []
                bestInterim = []

                lock.lock()
                if !accumulatedText.isEmpty && !accumulatedText.hasSuffix(" ") {
                    accumulatedText += " "
                }
                accumulatedText += resultTranscript
                latestInterimText = ""
                lock.unlock()

                DispatchQueue.main.async {
                    self.onFinalResult?(resultTranscript)
                }

            } else {
                logWords("interim", transcript: transcript, words: alternative.words)

                // Track interim words for bestInterim calculation
                if let words = alternative.words, !words.isEmpty {
                    interimHistory.append(words)
                    updateBestInterim()
                    logInterimState()
                }

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

    // MARK: - Word Tracking Logic

    /// Incremental bestInterim update: compare new interim with previous one.
    private func updateBestInterim() {
        let newInterim = interimHistory.last!

        // First interim — initialize
        if interimHistory.count == 1 {
            bestInterim = newInterim
            return
        }

        let previousInterim = interimHistory[interimHistory.count - 2]

        for newWord in newInterim {
            // Skip words with stable time range — unchanged from previous interim
            if isTimeStable(newWord, in: previousInterim) {
                // Update confidence in bestInterim if higher
                if let idx = bestInterim.firstIndex(where: {
                    isSameWordAndTime($0, newWord)
                }), newWord.confidence > bestInterim[idx].confidence {
                    print("[Deepgram] TRACK: stable \"\(newWord.word)\" confidence \(formatConf(bestInterim[idx].confidence))→\(formatConf(newWord.confidence))")
                    bestInterim[idx] = newWord
                }
                continue
            }

            // Changed word — find what it overlaps in bestInterim
            let overlapping = bestInterim.enumerated().filter { hasTimeOverlap($0.element, newWord) }

            if overlapping.isEmpty {
                // New position — add
                print("[Deepgram] TRACK: new word \"\(newWord.word)\"(\(formatConf(newWord.confidence)))")
                bestInterim.append(newWord)
                continue
            }

            // Check if new word matches one of the overlapping words by text
            if let (matchIdx, matchWord) = overlapping.first(where: {
                $0.element.word.lowercased() == newWord.word.lowercased()
            }) {
                // Matches one word — absorption case
                // Update confidence if higher
                if newWord.confidence > matchWord.confidence {
                    print("[Deepgram] TRACK: update \"\(newWord.word)\" confidence \(formatConf(matchWord.confidence))→\(formatConf(newWord.confidence))")
                    bestInterim[matchIdx] = newWord
                }
                // Other overlapping words are absorbed — KEEP them in bestInterim
                let absorbed = overlapping.filter { $0.offset != matchIdx }
                for (_, absWord) in absorbed {
                    print("[Deepgram] TRACK: ABSORBED \"\(absWord.word)\" — keeping in bestInterim")
                }
            } else {
                // Doesn't match any — potential complete revision
                if overlapping.count == 1 {
                    // Single replacement
                    let (idx, existing) = overlapping[0]
                    if newWord.confidence > existing.confidence {
                        print("[Deepgram] TRACK: replace \"\(existing.word)\"(\(formatConf(existing.confidence))) → \"\(newWord.word)\"(\(formatConf(newWord.confidence)))")
                        bestInterim[idx] = newWord
                    } else {
                        print("[Deepgram] TRACK: keep \"\(existing.word)\"(\(formatConf(existing.confidence))), rejected \"\(newWord.word)\"(\(formatConf(newWord.confidence)))")
                    }
                } else {
                    // Overlaps multiple, matches none — complete revision
                    let allLower = overlapping.allSatisfy { newWord.confidence > $0.element.confidence }
                    if allLower {
                        let removed = overlapping.map { $0.element.word }.joined(separator: ", ")
                        print("[Deepgram] TRACK: revision \"\(removed)\" → \"\(newWord.word)\"(\(formatConf(newWord.confidence)))")
                        let indicesToRemove = Set(overlapping.map { $0.offset })
                        bestInterim = bestInterim.enumerated()
                            .filter { !indicesToRemove.contains($0.offset) }
                            .map { $0.element }
                        bestInterim.append(newWord)
                    } else {
                        print("[Deepgram] TRACK: revision rejected, keeping originals")
                    }
                }
            }
        }

        bestInterim.sort { $0.start < $1.start }
    }

    /// Check if word has identical text and time range in another interim.
    private func isTimeStable(_ word: DeepgramWord, in other: [DeepgramWord]) -> Bool {
        other.contains {
            $0.word.lowercased() == word.word.lowercased()
            && abs($0.start - word.start) < 0.05
            && abs($0.end - word.end) < 0.05
        }
    }

    /// Check if two words have same text and approximately same time.
    private func isSameWordAndTime(_ a: DeepgramWord, _ b: DeepgramWord) -> Bool {
        a.word.lowercased() == b.word.lowercased()
        && abs(a.start - b.start) < 0.05
        && abs(a.end - b.end) < 0.05
    }

    private func formatConf(_ c: Double) -> String {
        String(format: "%.2f", c)
    }

    private func patchFinalWithBestInterim(finalWords: [DeepgramWord], finalTranscript: String) -> String {
        // Find bestInterim words missing from FINAL (by text + time overlap)
        var missingWords: [DeepgramWord] = []

        for bestWord in bestInterim {
            let existsInFinal = finalWords.contains {
                hasTimeOverlap($0, bestWord)
                && $0.word.lowercased() == bestWord.word.lowercased()
            }
            if !existsInFinal {
                missingWords.append(bestWord)
            }
        }

        guard !missingWords.isEmpty else {
            print("[Deepgram] PATCH: no missing words, using FINAL as-is")
            return finalTranscript
        }

        // Insert missing words using bestInterim order
        var result = finalTranscript
        for missing in missingWords {
            // Find the next word in bestInterim after this one that exists in FINAL
            let missingBestIdx = bestInterim.firstIndex(where: {
                $0.word == missing.word && abs($0.start - missing.start) < 0.05
            })
            var inserted = false

            if let mIdx = missingBestIdx {
                // Look forward in bestInterim for an anchor word present in FINAL
                for nextBest in bestInterim[(mIdx + 1)...] {
                    if let range = result.range(of: nextBest.word, options: .caseInsensitive) {
                        result.insert(contentsOf: "\(missing.word) ", at: range.lowerBound)
                        inserted = true
                        break
                    }
                }
            }

            if !inserted {
                // No anchor after — append at end (before trailing punctuation)
                let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
                if let last = trimmed.last, ".!?".contains(last) {
                    let insertIdx = result.index(result.startIndex,
                        offsetBy: trimmed.count - 1)
                    result.insert(contentsOf: " \(missing.word)", at: insertIdx)
                } else {
                    result += " " + missing.word
                }
            }
        }

        print("[Deepgram] PATCH: restored \(missingWords.count) word(s): " +
              "\(missingWords.map { $0.word }.joined(separator: ", "))")
        print("[Deepgram] PATCH result: \"\(result)\"")
        return result
    }

    private func hasTimeOverlap(_ a: DeepgramWord, _ b: DeepgramWord) -> Bool {
        return a.start < b.end && b.start < a.end
    }

    private func calculateRMS(_ data: Data) -> Double {
        data.withUnsafeBytes { buffer in
            let samples = buffer.bindMemory(to: Int16.self)
            let sumOfSquares = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
            return sqrt(sumOfSquares / Double(samples.count))
        }
    }

    // MARK: - Logging

    private func logWords(_ label: String, transcript: String, words: [DeepgramWord]?) {
        guard let words, !words.isEmpty else {
            print("[Deepgram] \(label): \"\(transcript)\"")
            return
        }
        let wordDetails = words.map {
            "\($0.word)(\(String(format: "%.2f", $0.confidence)) " +
            "\(String(format: "%.2f", $0.start))-\(String(format: "%.2f", $0.end)))"
        }.joined(separator: " ")
        print("[Deepgram] \(label): \"\(transcript)\" | words: [\(wordDetails)]")
    }

    private func logInterimState() {
        print("[Deepgram] === TRACKING (\(interimHistory.count) interims) ===")
        for (i, interim) in interimHistory.enumerated() {
            print("[Deepgram]   [\(i)]: \(formatWordsCompact(interim))")
        }
        print("[Deepgram]   best: \(formatWordsCompact(bestInterim))")
    }

    private func formatWordsCompact(_ words: [DeepgramWord]) -> String {
        words.map { "\($0.word)(\(String(format: "%.2f", $0.confidence)))" }
            .joined(separator: " ")
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
    let words: [DeepgramWord]?
}

struct DeepgramWord: Decodable {
    let word: String
    let start: Double
    let end: Double
    let confidence: Double
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
