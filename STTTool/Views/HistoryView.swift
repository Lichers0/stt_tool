import SwiftUI

struct HistoryView: View {
    @ObservedObject var viewModel: HistoryViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .padding(.horizontal, DS.Spacing.lg)
            if viewModel.records.isEmpty {
                emptyState
            } else {
                recordsList
            }
        }
    }

    private var header: some View {
        HStack {
            Text("History")
                .font(DS.Typography.header)
            Spacer()
            if !viewModel.records.isEmpty {
                ActionButton(
                    icon: "trash",
                    text: "Clear All",
                    destructive: true
                ) {
                    viewModel.clearAll()
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.lg)
        .padding(.bottom, DS.Spacing.sm)
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.sm) {
            Spacer()
            Image(systemName: "text.bubble")
                .font(.system(size: 28))
                .foregroundStyle(.secondary.opacity(0.3))
            Text("No transcriptions yet")
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(height: 200)
    }

    private var recordsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.records.enumerated()), id: \.element.id) { index, record in
                    RecordRowView(
                        record: record,
                        onCopy: { viewModel.copyToClipboard(record.text) },
                        onDelete: {
                            if let idx = viewModel.records.firstIndex(where: { $0.id == record.id }) {
                                viewModel.delete(at: IndexSet(integer: idx))
                            }
                        }
                    )
                    if index < viewModel.records.count - 1 {
                        Divider()
                            .padding(.horizontal, DS.Spacing.lg)
                    }
                }
            }
            .padding(.bottom, DS.Spacing.lg)
        }
        .frame(maxHeight: 340)
    }
}

// MARK: - Record Row

private struct RecordRowView: View {
    let record: TranscriptionRecord
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(record.text)
                .font(.system(size: 12))
                .lineLimit(3)
                .textSelection(.enabled)
                .foregroundStyle(.primary)

            HStack {
                if let lang = record.language {
                    StatusBadge(text: lang.uppercased())
                }
                Text(record.date, style: .relative)
                    .font(DS.Typography.tinyLabel)
                    .foregroundStyle(.secondary)
                Text(record.modelName)
                    .font(DS.Typography.tinyLabel)
                    .foregroundStyle(.secondary.opacity(0.6))

                Spacer()

                HStack(spacing: 2) {
                    ActionButton(icon: "doc.on.doc", action: onCopy)
                    ActionButton(icon: "trash", destructive: true, action: onDelete)
                }
                .opacity(isHovering ? 1 : 0)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .background(isHovering ? DS.Colors.surfaceHover : Color.clear)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovering = hovering }
        }
    }
}
