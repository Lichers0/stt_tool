import Foundation

final class HistoryService: HistoryServiceProtocol {
    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private(set) var records: [TranscriptionRecord] = []

    init() {
        load()
    }

    func add(_ record: TranscriptionRecord) {
        records.insert(record, at: 0)
        if records.count > Constants.maxHistoryRecords {
            records = Array(records.prefix(Constants.maxHistoryRecords))
        }
        save()
    }

    func remove(at offsets: IndexSet) {
        records.remove(atOffsets: offsets)
        save()
    }

    func clearAll() {
        records.removeAll()
        save()
    }

    // MARK: - Private

    private func load() {
        guard let data = defaults.data(forKey: Constants.historyKey) else { return }
        do {
            records = try decoder.decode([TranscriptionRecord].self, from: data)
        } catch {
            records = []
        }
    }

    private func save() {
        do {
            let data = try encoder.encode(records)
            defaults.set(data, forKey: Constants.historyKey)
        } catch {
            // Silently fail -- history is not critical
        }
    }
}
