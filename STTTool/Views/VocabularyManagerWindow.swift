import AppKit
import Combine
import SwiftUI

// MARK: - Window Controller

final class VocabularyManagerWindow: NSWindow {

    private static var shared: VocabularyManagerWindow?

    static func showShared() {
        if let existing = shared, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let window = VocabularyManagerWindow()
        shared = window
        window.makeKeyAndOrderFront(nil)
        window.center()
    }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 460),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: true
        )

        title = "Vocabulary Manager"
        minSize = NSSize(width: 500, height: 350)
        isReleasedWhenClosed = false

        let view = VocabularyManagerView()
        contentView = NSHostingView(rootView: view)
    }
}

// MARK: - Main View

struct VocabularyManagerView: View {
    @StateObject private var viewModel = VocabularyManagerViewModel()

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                sidebarView
                    .frame(minWidth: 180)
            } detail: {
                detailView
            }

            if let service = VocabularyServiceShared.instance as? VocabularyService {
                Divider()
                VocabularyManagerFooter(
                    service: service,
                    vocabularies: viewModel.sortedVocabularies
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .frame(minWidth: 500, minHeight: 360)
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        VStack(spacing: 0) {
            List(selection: $viewModel.selectedVocabularyId) {
                ForEach(viewModel.sortedVocabularies) { vocab in
                    VocabularySidebarRow(
                        vocabulary: vocab,
                        isActive: vocab.id == viewModel.activeVocabularyId,
                        isEditing: viewModel.renamingId == vocab.id,
                        editedName: $viewModel.editedName,
                        onCommitRename: { viewModel.commitRename() },
                        onCancelRename: { viewModel.cancelRename() }
                    )
                    .tag(vocab.id)
                }
                .onMove { source, destination in
                    viewModel.reorder(from: source, to: destination)
                }
            }
            .listStyle(.sidebar)

            // Toolbar
            HStack(spacing: 12) {
                Button(action: viewModel.createNew) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("New vocabulary")

                Button(action: viewModel.duplicateSelected) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .disabled(viewModel.selectedVocabularyId == nil)
                .help("Duplicate")

                Button(action: viewModel.renameSelected) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .disabled(viewModel.selectedVocabularyId == nil)
                .help("Rename")

                Spacer()

                Button(action: viewModel.deleteSelected) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .disabled(viewModel.selectedVocabularyId == nil || viewModel.sortedVocabularies.count <= 1)
                .help("Delete vocabulary")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        if let selected = viewModel.selectedVocabulary {
            VocabularyDetailView(
                vocabulary: selected,
                otherVocabularies: viewModel.otherVocabularies,
                onAddTerm: { viewModel.addTerm($0) },
                onRemoveTerm: { viewModel.removeTerm($0) },
                onCopyTerms: { terms, targetId in viewModel.copyTerms(terms, to: targetId) },
                onMoveTerms: { terms, targetId in viewModel.moveTerms(terms, to: targetId) },
                onDeleteTerms: { viewModel.deleteTerms($0) }
            )
        } else {
            Text("Select a vocabulary")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Sidebar Row

struct VocabularySidebarRow: View {
    let vocabulary: Vocabulary
    let isActive: Bool
    let isEditing: Bool
    @Binding var editedName: String
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void

    var body: some View {
        HStack {
            if isActive {
                Circle()
                    .fill(.blue)
                    .frame(width: 6, height: 6)
            }

            if isEditing {
                TextField("Name", text: $editedName, onCommit: onCommitRename)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .onExitCommand(perform: onCancelRename)
            } else {
                VStack(alignment: .leading) {
                    Text(vocabulary.name)
                        .fontWeight(isActive ? .semibold : .regular)
                    Text("\(vocabulary.terms.count) terms")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Detail View

struct VocabularyDetailView: View {
    let vocabulary: Vocabulary
    let otherVocabularies: [Vocabulary]
    let onAddTerm: (String) -> Void
    let onRemoveTerm: (String) -> Void
    let onCopyTerms: ([String], UUID) -> Void
    let onMoveTerms: ([String], UUID) -> Void
    let onDeleteTerms: ([String]) -> Void

    @State private var newTerm = ""
    @State private var isSelectionMode = false
    @State private var selectedTerms: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(vocabulary.name)
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                if isSelectionMode {
                    selectionToolbar
                } else {
                    Button(action: { isSelectionMode = true }) {
                        Image(systemName: "checkmark.circle")
                            .font(.body)
                    }
                    .buttonStyle(.plain)
                    .disabled(vocabulary.terms.isEmpty)
                    .help("Select terms")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Add term
            HStack {
                TextField("Add term", text: $newTerm)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addTerm() }
                Button(action: { addTerm() }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .disabled(newTerm.isEmpty || vocabulary.terms.count >= 100)
                .help("Add term")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Term list
            List {
                ForEach(vocabulary.terms, id: \.self) { term in
                    termRow(term)
                }
            }
            .listStyle(.plain)

            // Footer: term count
            HStack {
                Text("\(vocabulary.terms.count) / 100 terms")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .onChange(of: vocabulary.id) {
            isSelectionMode = false
            selectedTerms.removeAll()
        }
    }

    @ViewBuilder
    private func termRow(_ term: String) -> some View {
        HStack {
            if isSelectionMode {
                Image(systemName: selectedTerms.contains(term) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedTerms.contains(term) ? .blue : .secondary)
                    .onTapGesture {
                        if selectedTerms.contains(term) {
                            selectedTerms.remove(term)
                        } else {
                            selectedTerms.insert(term)
                        }
                    }
            }

            Text(term)
                .font(.body)

            Spacer()

            if !isSelectionMode {
                Button(action: { onRemoveTerm(term) }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(0.5)
            }
        }
    }

    private var selectionToolbar: some View {
        HStack(spacing: 8) {
            Button(action: { selectedTerms = Set(vocabulary.terms) }) {
                Image(systemName: "checkmark.square.fill")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .help("Select all")

            Button(action: { selectedTerms.removeAll() }) {
                Image(systemName: "square")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .help("Deselect all")

            if !otherVocabularies.isEmpty {
                Menu {
                    ForEach(otherVocabularies) { vocab in
                        Button(vocab.name) {
                            onCopyTerms(Array(selectedTerms), vocab.id)
                        }
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.body)
                }
                .disabled(selectedTerms.isEmpty)
                .help("Copy to...")

                Menu {
                    ForEach(otherVocabularies) { vocab in
                        Button(vocab.name) {
                            onMoveTerms(Array(selectedTerms), vocab.id)
                            selectedTerms.removeAll()
                        }
                    }
                } label: {
                    Image(systemName: "arrow.right.doc.on.clipboard")
                        .font(.body)
                }
                .disabled(selectedTerms.isEmpty)
                .help("Move to...")
            }

            Button(action: {
                onDeleteTerms(Array(selectedTerms))
                selectedTerms.removeAll()
            }) {
                Image(systemName: "trash")
                    .font(.body)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .disabled(selectedTerms.isEmpty)
            .help("Delete selected")

            Button(action: {
                isSelectionMode = false
                selectedTerms.removeAll()
            }) {
                Image(systemName: "xmark.circle")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .help("Done")
        }
    }

    private func addTerm() {
        guard !newTerm.isEmpty else { return }
        onAddTerm(newTerm)
        newTerm = ""
    }
}

// MARK: - ViewModel

@MainActor
final class VocabularyManagerViewModel: ObservableObject {
    @Published var selectedVocabularyId: UUID?
    @Published var renamingId: UUID?
    @Published var editedName = ""

    private var vocabularyService: VocabularyServiceProtocol {
        // Access from shared ServiceContainer -- there's only one in the app lifecycle
        _vocabularyService
    }
    private let _vocabularyService: VocabularyServiceProtocol

    var sortedVocabularies: [Vocabulary] {
        vocabularyService.vocabularies.sorted { $0.sortOrder < $1.sortOrder }
    }

    var activeVocabularyId: UUID? {
        vocabularyService.activeVocabularyId
    }

    var selectedVocabulary: Vocabulary? {
        guard let id = selectedVocabularyId else { return nil }
        return vocabularyService.vocabularies.first { $0.id == id }
    }

    var otherVocabularies: [Vocabulary] {
        vocabularyService.vocabularies.filter { $0.id != selectedVocabularyId }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    init() {
        // Resolve from the shared ServiceContainer singleton
        _vocabularyService = VocabularyManagerViewModel.resolveService()
        selectedVocabularyId = vocabularyService.activeVocabularyId
            ?? vocabularyService.vocabularies.sorted(by: { $0.sortOrder < $1.sortOrder }).first?.id

        // Observe changes from VocabularyService to refresh UI
        if let observable = _vocabularyService as? VocabularyService {
            observable.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        }
    }

    private var cancellables: Set<AnyCancellable> = []

    private static func resolveService() -> VocabularyServiceProtocol {
        // We need a way to get the shared VocabularyService.
        // The service is stored in ServiceContainer which is created in STTToolApp.
        // For now, use the shared instance pattern.
        return VocabularyServiceShared.instance
    }

    // MARK: - Actions

    func createNew() {
        let vocab = vocabularyService.createVocabulary(name: "New Vocabulary", terms: [])
        selectedVocabularyId = vocab.id
    }

    func duplicateSelected() {
        guard let id = selectedVocabularyId else { return }
        vocabularyService.duplicateVocabulary(id)
    }

    func deleteSelected() {
        guard let id = selectedVocabularyId else { return }
        vocabularyService.deleteVocabulary(id)
        selectedVocabularyId = sortedVocabularies.first?.id
    }

    func renameSelected() {
        guard let id = selectedVocabularyId,
              let vocab = vocabularyService.vocabularies.first(where: { $0.id == id }) else { return }
        renamingId = id
        editedName = vocab.name
    }

    func commitRename() {
        guard let id = renamingId,
              var vocab = vocabularyService.vocabularies.first(where: { $0.id == id }) else { return }
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            vocab.name = trimmed
            vocabularyService.updateVocabulary(vocab)
        }
        renamingId = nil
    }

    func cancelRename() {
        renamingId = nil
    }

    func reorder(from source: IndexSet, to destination: Int) {
        vocabularyService.reorder(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Term Management

    func addTerm(_ term: String) {
        guard let id = selectedVocabularyId else { return }
        vocabularyService.addTerm(term, to: id)
    }

    func removeTerm(_ term: String) {
        guard let id = selectedVocabularyId else { return }
        vocabularyService.removeTerm(term, from: id)
    }

    func deleteTerms(_ terms: [String]) {
        guard let id = selectedVocabularyId else { return }
        for term in terms {
            vocabularyService.removeTerm(term, from: id)
        }
    }

    func copyTerms(_ terms: [String], to targetId: UUID) {
        vocabularyService.copyTerms(terms, to: targetId)
    }

    func moveTerms(_ terms: [String], to targetId: UUID) {
        guard let id = selectedVocabularyId else { return }
        vocabularyService.moveTerms(terms, from: id, to: targetId)
    }
}

// MARK: - Footer for default vocabulary

struct VocabularyManagerFooter: View {
    @ObservedObject var service: VocabularyService
    let vocabularies: [Vocabulary]

    var body: some View {
        HStack {
            Text("Default vocabulary:")
                .font(.caption)

            Picker("", selection: Binding(
                get: { service.startupMode },
                set: { service.startupMode = $0 }
            )) {
                Text("Last used").tag(VocabularyStartupMode.last)
                Text("Specific").tag(VocabularyStartupMode.specific)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            if service.startupMode == .specific {
                Picker("", selection: Binding(
                    get: { service.defaultVocabularyId ?? vocabularies.first?.id ?? UUID() },
                    set: { service.defaultVocabularyId = $0 }
                )) {
                    ForEach(vocabularies) { vocab in
                        Text(vocab.name).tag(vocab.id)
                    }
                }
                .frame(width: 140)
            }
        }
    }
}
