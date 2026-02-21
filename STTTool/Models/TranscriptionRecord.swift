import Foundation

struct TranscriptionRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let language: String?
    let date: Date
    let modelName: String
    let durationSeconds: Double

    init(
        id: UUID = UUID(),
        text: String,
        language: String? = nil,
        date: Date = Date(),
        modelName: String,
        durationSeconds: Double
    ) {
        self.id = id
        self.text = text
        self.language = language
        self.date = date
        self.modelName = modelName
        self.durationSeconds = durationSeconds
    }
}
