import Foundation

final class DeepgramRESTService: DeepgramRESTServiceProtocol, @unchecked Sendable {

    func transcribe(audioData: Data, apiKey: String, vocabulary: [String]) async throws -> String {
        var components = URLComponents(string: Constants.deepgramRESTURL)!
        var queryItems = [
            URLQueryItem(name: "model", value: Constants.deepgramModel),
            URLQueryItem(name: "language", value: "multi"),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "detect_language", value: "true"),
        ]

        for term in vocabulary.prefix(100) {
            queryItems.append(URLQueryItem(name: "keyterm", value: term))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw DeepgramError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = createWAVData(from: audioData)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepgramError.serverError("Invalid response")
        }

        if httpResponse.statusCode == 401 {
            throw DeepgramError.invalidAPIKey
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw DeepgramError.serverError("HTTP \(httpResponse.statusCode): \(body)")
        }

        let result = try JSONDecoder().decode(DeepgramRESTResponse.self, from: data)
        return result.results?.channels?.first?.alternatives?.first?.transcript ?? ""
    }

    // MARK: - WAV Header

    private func createWAVData(from pcmData: Data) -> Data {
        let sampleRate: UInt32 = 16000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(pcmData.count)

        var header = Data()

        // RIFF header
        header.append(contentsOf: "RIFF".utf8)
        header.append(withUnsafeBytes(of: (36 + dataSize).littleEndian) { Data($0) })
        header.append(contentsOf: "WAVE".utf8)

        // fmt subchunk
        header.append(contentsOf: "fmt ".utf8)
        header.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })      // PCM
        header.append(withUnsafeBytes(of: channels.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })

        // data subchunk
        header.append(contentsOf: "data".utf8)
        header.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })

        return header + pcmData
    }
}

// MARK: - REST Response Models

struct DeepgramRESTResponse: Decodable {
    let results: DeepgramRESTResults?
}

struct DeepgramRESTResults: Decodable {
    let channels: [DeepgramRESTChannel]?
}

struct DeepgramRESTChannel: Decodable {
    let alternatives: [DeepgramAlternative]?
}
