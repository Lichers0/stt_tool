import AppKit
import Foundation

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var records: [TranscriptionRecord] = []

    private let historyService: HistoryServiceProtocol

    init(historyService: HistoryServiceProtocol) {
        self.historyService = historyService
        refresh()
    }

    func refresh() {
        records = historyService.records
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func delete(at offsets: IndexSet) {
        historyService.remove(at: offsets)
        refresh()
    }

    func clearAll() {
        historyService.clearAll()
        refresh()
    }
}
