import Foundation
import Combine

// MARK: - Startup Mode

enum VocabularyStartupMode: String {
    case last = "last"
    case specific = "specific"
}

// MARK: - Shared Instance Accessor

/// Provides access to the VocabularyService from windows that don't have ServiceContainer reference.
enum VocabularyServiceShared {
    @MainActor static var instance: VocabularyServiceProtocol!
}

// MARK: - Service Implementation

@MainActor
final class VocabularyService: VocabularyServiceProtocol, ObservableObject {

    @Published private(set) var vocabularies: [Vocabulary] = []
    @Published private(set) var activeVocabularyId: UUID?

    private let defaults = UserDefaults.standard

    init() {
        migrateIfNeeded()
        vocabularies = loadVocabularies()
        activeVocabularyId = resolveActiveId()
    }

    // MARK: - Active Vocabulary

    var activeVocabulary: Vocabulary? {
        if let id = activeVocabularyId, let vocab = vocabularies.first(where: { $0.id == id }) {
            return vocab
        }
        return vocabularies.sorted(by: { $0.sortOrder < $1.sortOrder }).first
    }

    func setActiveVocabulary(_ id: UUID) {
        activeVocabularyId = id
        defaults.set(id.uuidString, forKey: Constants.activeVocabularyIdKey)
    }

    // MARK: - CRUD

    @discardableResult
    func createVocabulary(name: String, terms: [String] = []) -> Vocabulary {
        let maxOrder = vocabularies.map(\.sortOrder).max() ?? -1
        let vocab = Vocabulary(name: name, terms: terms, sortOrder: maxOrder + 1)
        vocabularies.append(vocab)
        save()
        return vocab
    }

    func updateVocabulary(_ vocabulary: Vocabulary) {
        guard let idx = vocabularies.firstIndex(where: { $0.id == vocabulary.id }) else { return }
        vocabularies[idx] = vocabulary
        save()
    }

    func deleteVocabulary(_ id: UUID) {
        vocabularies.removeAll { $0.id == id }
        if activeVocabularyId == id {
            activeVocabularyId = vocabularies.sorted(by: { $0.sortOrder < $1.sortOrder }).first?.id
            if let newId = activeVocabularyId {
                defaults.set(newId.uuidString, forKey: Constants.activeVocabularyIdKey)
            }
        }
        // Ensure at least one vocabulary exists
        if vocabularies.isEmpty {
            createVocabulary(name: "General")
        }
        save()
    }

    func duplicateVocabulary(_ id: UUID) {
        guard let original = vocabularies.first(where: { $0.id == id }) else { return }
        createVocabulary(name: "\(original.name) (copy)", terms: original.terms)
    }

    // MARK: - Reorder

    func reorder(fromOffsets source: IndexSet, toOffset destination: Int) {
        vocabularies.move(fromOffsets: source, toOffset: destination)
        for i in vocabularies.indices {
            vocabularies[i].sortOrder = i
        }
        save()
    }

    // MARK: - Term Management

    func addTerm(_ term: String, to vocabularyId: UUID) {
        guard let idx = vocabularies.firstIndex(where: { $0.id == vocabularyId }) else { return }
        guard !term.isEmpty, !vocabularies[idx].terms.contains(term) else { return }
        guard vocabularies[idx].terms.count < 100 else { return }
        vocabularies[idx].terms.append(term)
        save()
    }

    func removeTerm(_ term: String, from vocabularyId: UUID) {
        guard let idx = vocabularies.firstIndex(where: { $0.id == vocabularyId }) else { return }
        vocabularies[idx].terms.removeAll { $0 == term }
        save()
    }

    func removeTerms(at offsets: IndexSet, from vocabularyId: UUID) {
        guard let idx = vocabularies.firstIndex(where: { $0.id == vocabularyId }) else { return }
        vocabularies[idx].terms.remove(atOffsets: offsets)
        save()
    }

    func copyTerms(_ terms: [String], to targetId: UUID) {
        guard let idx = vocabularies.firstIndex(where: { $0.id == targetId }) else { return }
        let existing = Set(vocabularies[idx].terms)
        let newTerms = terms.filter { !existing.contains($0) }
        vocabularies[idx].terms.append(contentsOf: newTerms)
        save()
    }

    func moveTerms(_ terms: [String], from sourceId: UUID, to targetId: UUID) {
        copyTerms(terms, to: targetId)
        guard let srcIdx = vocabularies.firstIndex(where: { $0.id == sourceId }) else { return }
        vocabularies[srcIdx].terms.removeAll { terms.contains($0) }
        save()
    }

    // MARK: - Cycling (for overlay)

    func vocabularyBySortOrder() -> [Vocabulary] {
        vocabularies.sorted { $0.sortOrder < $1.sortOrder }
    }

    func nextVocabulary(after currentId: UUID) -> Vocabulary? {
        let sorted = vocabularyBySortOrder()
        guard let currentIdx = sorted.firstIndex(where: { $0.id == currentId }) else {
            return sorted.first
        }
        let nextIdx = (currentIdx + 1) % sorted.count
        return sorted[nextIdx]
    }

    func previousVocabulary(before currentId: UUID) -> Vocabulary? {
        let sorted = vocabularyBySortOrder()
        guard let currentIdx = sorted.firstIndex(where: { $0.id == currentId }) else {
            return sorted.last
        }
        let prevIdx = (currentIdx - 1 + sorted.count) % sorted.count
        return sorted[prevIdx]
    }

    // MARK: - Startup Mode

    var startupMode: VocabularyStartupMode {
        get {
            let raw = defaults.string(forKey: Constants.vocabularyStartupModeKey) ?? "last"
            return VocabularyStartupMode(rawValue: raw) ?? .last
        }
        set {
            defaults.set(newValue.rawValue, forKey: Constants.vocabularyStartupModeKey)
        }
    }

    var defaultVocabularyId: UUID? {
        get {
            guard let str = defaults.string(forKey: Constants.defaultVocabularyIdKey) else { return nil }
            return UUID(uuidString: str)
        }
        set {
            if let id = newValue {
                defaults.set(id.uuidString, forKey: Constants.defaultVocabularyIdKey)
            } else {
                defaults.removeObject(forKey: Constants.defaultVocabularyIdKey)
            }
        }
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(vocabularies) else { return }
        defaults.set(data, forKey: Constants.vocabulariesKey)
    }

    private func loadVocabularies() -> [Vocabulary] {
        guard let data = defaults.data(forKey: Constants.vocabulariesKey),
              let vocabs = try? JSONDecoder().decode([Vocabulary].self, from: data) else {
            return []
        }
        return vocabs.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func resolveActiveId() -> UUID? {
        if startupMode == .specific, let defaultId = defaultVocabularyId,
           vocabularies.contains(where: { $0.id == defaultId }) {
            return defaultId
        }
        if let savedStr = defaults.string(forKey: Constants.activeVocabularyIdKey),
           let savedId = UUID(uuidString: savedStr),
           vocabularies.contains(where: { $0.id == savedId }) {
            return savedId
        }
        return vocabularies.sorted(by: { $0.sortOrder < $1.sortOrder }).first?.id
    }

    // MARK: - Migration

    private func migrateIfNeeded() {
        // Already migrated
        if defaults.data(forKey: Constants.vocabulariesKey) != nil { return }

        let oldTerms = defaults.stringArray(forKey: Constants.vocabularyTermsKey) ?? []

        if !oldTerms.isEmpty {
            // Migrate old flat terms into "General" vocabulary
            let general = Vocabulary(name: "General", terms: oldTerms, sortOrder: 0)
            if let data = try? JSONEncoder().encode([general]) {
                defaults.set(data, forKey: Constants.vocabulariesKey)
                defaults.set(general.id.uuidString, forKey: Constants.activeVocabularyIdKey)
            }
            defaults.removeObject(forKey: Constants.vocabularyTermsKey)
        } else {
            // First launch: create empty starter vocabulary
            let general = Vocabulary(name: "General", terms: [], sortOrder: 0)
            if let data = try? JSONEncoder().encode([general]) {
                defaults.set(data, forKey: Constants.vocabulariesKey)
                defaults.set(general.id.uuidString, forKey: Constants.activeVocabularyIdKey)
            }
        }
    }
}
