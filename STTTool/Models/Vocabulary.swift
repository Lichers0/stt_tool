import Foundation

struct Vocabulary: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var terms: [String]
    var sortOrder: Int

    init(id: UUID = UUID(), name: String, terms: [String] = [], sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.terms = terms
        self.sortOrder = sortOrder
    }
}
