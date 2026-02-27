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
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 460),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: true
        )

        title = "Vocabulary Manager"
        minSize = NSSize(width: 540, height: 380)
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
            // Two-panel layout with visible divider
            HStack(spacing: 0) {
                sidebarView
                    .frame(minWidth: 180, maxWidth: 220)

                // Visible divider between panels
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)

                detailView
                    .frame(maxWidth: .infinity)
            }

            Divider()

            // Footer
            if let service = VocabularyServiceShared.instance as? VocabularyService {
                VocabularyManagerFooter(
                    service: service,
                    vocabularies: viewModel.sortedVocabularies
                )
            }
        }
        .frame(minWidth: 540, minHeight: 380)
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        VStack(spacing: 0) {
            // Vocabulary list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.sortedVocabularies) { vocab in
                        VocabularySidebarRow(
                            vocabulary: vocab,
                            isSelected: vocab.id == viewModel.selectedVocabularyId,
                            isActive: vocab.id == viewModel.indicatedVocabularyId,
                            isEditing: viewModel.renamingId == vocab.id,
                            editedName: $viewModel.editedName,
                            onSelect: {
                                viewModel.selectedVocabularyId = vocab.id
                            },
                            onDoubleClick: {
                                viewModel.selectedVocabularyId = vocab.id
                                viewModel.renameSelected()
                            },
                            onCommitRename: { viewModel.commitRename() },
                            onCancelRename: { viewModel.cancelRename() }
                        )
                    }
                }
                .padding(.vertical, 2)
            }

            Divider()

            // Sidebar toolbar
            HStack(spacing: 2) {
                HStack(spacing: 2) {
                    ActionButton(icon: "plus") { viewModel.createNew() }
                        .help("New vocabulary")
                    ActionButton(icon: "doc.on.doc") { viewModel.duplicateSelected() }
                        .disabled(viewModel.selectedVocabularyId == nil)
                        .help("Duplicate")
                    ActionButton(icon: "pencil") { viewModel.renameSelected() }
                        .disabled(viewModel.selectedVocabularyId == nil)
                        .help("Rename")
                }
                Spacer()
                ActionButton(icon: "trash", destructive: true) { viewModel.deleteSelected() }
                    .disabled(viewModel.selectedVocabularyId == nil || viewModel.sortedVocabularies.count <= 1)
                    .help("Delete vocabulary")
            }
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, 6)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
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
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Sidebar Row

private struct VocabularySidebarRow: View {
    let vocabulary: Vocabulary
    let isSelected: Bool
    let isActive: Bool
    let isEditing: Bool
    @Binding var editedName: String
    let onSelect: () -> Void
    let onDoubleClick: () -> Void
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            if isActive {
                Circle()
                    .fill(DS.Colors.primary)
                    .frame(width: 5, height: 5)
            }

            if isEditing {
                HStack(spacing: 4) {
                    TextField("Name", text: $editedName, onCommit: onCommitRename)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .onExitCommand(perform: onCancelRename)
                    Button(action: onCommitRename) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack {
                    Text(vocabulary.name)
                        .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Text("\(vocabulary.terms.count)")
                        .font(DS.Typography.tinyLabel)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .fill(isSelected
                      ? DS.Colors.primarySubtle
                      : isHovering ? DS.Colors.surfaceHover : Color.clear)
        )
        .padding(.horizontal, 4)
        .foregroundStyle(isSelected ? DS.Colors.primary : .primary)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onDoubleClick() }
        .onTapGesture(count: 1) { onSelect() }
        .onHover { hovering in isHovering = hovering }
    }
}

// MARK: - Detail View

private struct VocabularyDetailView: View {
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
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(vocabulary.name)
                    .font(DS.Typography.header)
                Spacer()
                if vocabulary.terms.count > 0 {
                    ActionButton(
                        icon: isSelectionMode ? "xmark" : "checkmark.circle",
                        text: isSelectionMode ? "Cancel" : "Select"
                    ) {
                        if isSelectionMode {
                            exitSelectionMode()
                        } else {
                            isSelectionMode = true
                        }
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)

            Divider()

            // Selection toolbar
            if isSelectionMode {
                selectionToolbar
                Divider()
            }

            // Add term (hidden during selection mode)
            if !isSelectionMode {
                HStack(spacing: DS.Spacing.sm) {
                    TextField("Add term...", text: $newTerm)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .onSubmit { addTerm() }
                    Button(action: addTerm) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: DS.Radius.md)
                                    .fill(newTerm.isEmpty || vocabulary.terms.count >= 100
                                          ? DS.Colors.primary.opacity(0.4)
                                          : DS.Colors.primary)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(newTerm.isEmpty || vocabulary.terms.count >= 100)
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, 10)
                Divider()
            }

            // Terms list
            ScrollView {
                if vocabulary.terms.isEmpty {
                    Text("No terms added yet")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(vocabulary.terms, id: \.self) { term in
                            TermRow(
                                term: term,
                                isSelectionMode: isSelectionMode,
                                isSelected: selectedTerms.contains(term),
                                onToggleSelection: { toggleTermSelection(term) },
                                onRemove: { onRemoveTerm(term) }
                            )
                        }
                    }
                }
            }

            // Footer: term count
            Divider()
            HStack {
                Spacer()
                Text("\(vocabulary.terms.count) / 100 terms")
                    .font(DS.Typography.tinyLabel)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)
        }
        .onChange(of: vocabulary.id) {
            exitSelectionMode()
        }
    }

    // MARK: - Selection Toolbar

    private var selectionToolbar: some View {
        HStack {
            HStack(spacing: DS.Spacing.sm) {
                ActionButton(
                    icon: selectedTerms.count == vocabulary.terms.count
                        ? "square" : "checkmark.square",
                    text: selectedTerms.count == vocabulary.terms.count
                        ? "Deselect all" : "Select all"
                ) {
                    if selectedTerms.count == vocabulary.terms.count {
                        selectedTerms.removeAll()
                    } else {
                        selectedTerms = Set(vocabulary.terms)
                    }
                }

                if selectedTerms.count > 0 {
                    Text("\(selectedTerms.count) selected")
                        .font(DS.Typography.tinyLabel)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if selectedTerms.count > 0 {
                HStack(spacing: 4) {
                    // Copy to
                    if !otherVocabularies.isEmpty {
                        Menu {
                            ForEach(otherVocabularies) { vocab in
                                Button(vocab.name) {
                                    onCopyTerms(Array(selectedTerms), vocab.id)
                                    exitSelectionMode()
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 10))
                                Text("Copy to")
                                    .font(.system(size: 10))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: DS.Radius.sm)
                                    .fill(Color.clear)
                            )
                        }
                        .menuStyle(.borderlessButton)

                        // Move to
                        Menu {
                            ForEach(otherVocabularies) { vocab in
                                Button(vocab.name) {
                                    onMoveTerms(Array(selectedTerms), vocab.id)
                                    exitSelectionMode()
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.right.arrow.left")
                                    .font(.system(size: 10))
                                Text("Move to")
                                    .font(.system(size: 10))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                        }
                        .menuStyle(.borderlessButton)
                    }

                    // Delete selected
                    ActionButton(icon: "trash", destructive: true) {
                        onDeleteTerms(Array(selectedTerms))
                        exitSelectionMode()
                    }
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .background(DS.Colors.surfaceHover)
    }

    // MARK: - Helpers

    private func addTerm() {
        let trimmed = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onAddTerm(trimmed)
        newTerm = ""
    }

    private func toggleTermSelection(_ term: String) {
        if selectedTerms.contains(term) {
            selectedTerms.remove(term)
        } else {
            selectedTerms.insert(term)
        }
    }

    private func exitSelectionMode() {
        isSelectionMode = false
        selectedTerms.removeAll()
    }
}

// MARK: - Term Row

private struct TermRow: View {
    let term: String
    let isSelectionMode: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? DS.Colors.primary : .secondary)
            }

            Text(term)
                .font(.system(size: 12))
                .foregroundStyle(.primary)

            Spacer()

            if !isSelectionMode {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(isHovering ? 0.8 : 0)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, 7)
        .background(
            isSelectionMode && isSelected
                ? DS.Colors.primarySubtle
                : isHovering ? DS.Colors.surfaceHover : Color.clear
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectionMode { onToggleSelection() }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovering = hovering }
        }
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

    /// Vocabulary that will be active on next recording session start
    var indicatedVocabularyId: UUID? {
        switch vocabularyService.startupMode {
        case .specific:
            return vocabularyService.defaultVocabularyId
                ?? vocabularyService.vocabularies.sorted(by: { $0.sortOrder < $1.sortOrder }).first?.id
        case .last:
            return vocabularyService.activeVocabularyId
        }
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
        renamingId = vocab.id
        editedName = vocab.name
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

// MARK: - Footer

private struct VocabularyManagerFooter: View {
    @ObservedObject var service: VocabularyService
    let vocabularies: [Vocabulary]

    private var isDefaultMode: Bool { service.startupMode == .specific }

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            Text("On startup use")
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)

            Picker("", selection: Binding(
                get: { service.defaultVocabularyId ?? vocabularies.first?.id ?? UUID() },
                set: { service.defaultVocabularyId = $0 }
            )) {
                ForEach(vocabularies) { vocab in
                    Text(vocab.name).tag(vocab.id)
                }
            }
            .frame(width: 140)
            .disabled(!isDefaultMode)
            .opacity(isDefaultMode ? 1.0 : 0.5)

            Spacer()

            SegmentedPicker(
                items: [("Last used", VocabularyStartupMode.last), ("Default", VocabularyStartupMode.specific)],
                selection: Binding(
                    get: { service.startupMode },
                    set: { service.startupMode = $0 }
                )
            )
            .frame(width: 180)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
    }
}
