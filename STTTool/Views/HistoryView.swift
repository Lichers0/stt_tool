import SwiftUI

struct HistoryView: View {
    @ObservedObject var viewModel: HistoryViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if viewModel.records.isEmpty {
                emptyState
            } else {
                recordsList
            }
        }
        .frame(width: 360, height: 400)
    }

    private var header: some View {
        HStack {
            Text("History")
                .font(.headline)
            Spacer()
            if !viewModel.records.isEmpty {
                Button("Clear All") {
                    viewModel.clearAll()
                }
                .font(.caption)
                .foregroundStyle(.red)
            }
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "text.bubble")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No transcriptions yet")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var recordsList: some View {
        List {
            ForEach(viewModel.records) { record in
                RecordRowView(record: record, onCopy: {
                    viewModel.copyToClipboard(record.text)
                })
            }
            .onDelete { offsets in
                viewModel.delete(at: offsets)
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Record Row

private struct RecordRowView: View {
    let record: TranscriptionRecord
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.text)
                .font(.body)
                .lineLimit(3)

            HStack {
                if let lang = record.language {
                    Text(lang.uppercased())
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
                Text(record.date, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("(\(record.modelName))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Copy to clipboard")
            }
        }
        .padding(.vertical, 4)
    }
}
