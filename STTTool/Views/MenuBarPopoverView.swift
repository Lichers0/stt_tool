import SwiftUI

struct MenuBarPopoverView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @State private var showingHistory = false
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 12) {
            headerView
            statusView
            recordButton
            lastTranscriptionView
            Divider()
            bottomBar
        }
        .padding(16)
        .frame(width: 320)
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack {
            Image(systemName: "mic.and.signal.meter")
                .font(.title3)
            Text("STT Tool")
                .font(.headline)
            Spacer()
            modelStatusBadge
        }
    }

    @ViewBuilder
    private var modelStatusBadge: some View {
        if viewModel.isLoadingModel {
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("Loading model...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else if viewModel.isModelLoaded {
            Text(viewModel.services.transcriptionService.currentModelName)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary)
                .clipShape(Capsule())
        } else if let error = viewModel.modelLoadError {
            Text(error)
                .font(.caption2)
                .foregroundStyle(.red)
                .lineLimit(1)
        }
    }

    private var statusView: some View {
        HStack {
            Image(systemName: viewModel.appState.systemImage)
                .foregroundStyle(stateColor)
                .symbolEffect(.pulse, isActive: viewModel.appState.isRecording)
            Text(viewModel.appState.statusText)
                .font(.subheadline)
                .foregroundStyle(stateColor)
            Spacer()
        }
    }

    private var recordButton: some View {
        Button(action: { viewModel.toggleRecording() }) {
            HStack {
                Image(systemName: viewModel.appState.isRecording ? "stop.fill" : "mic.fill")
                Text(viewModel.appState.isRecording ? "Stop Recording" : "Start Recording")
            }
            .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
        .tint(viewModel.appState.isRecording ? .red : .accentColor)
        .disabled(viewModel.appState == .transcribing || viewModel.appState == .inserting)
    }

    @ViewBuilder
    private var lastTranscriptionView: some View {
        if let record = viewModel.lastTranscription {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Last transcription")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let lang = record.language {
                        Text(lang.uppercased())
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                }
                Text(record.text)
                    .font(.body)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }
            .padding(8)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var bottomBar: some View {
        HStack {
            Button("History") {
                showingHistory = true
            }
            .popover(isPresented: $showingHistory) {
                HistoryView(
                    viewModel: HistoryViewModel(
                        historyService: viewModel.services.historyService
                    )
                )
            }

            Spacer()

            Button("Settings") {
                showingSettings = true
            }
            .popover(isPresented: $showingSettings) {
                SettingsView(
                    viewModel: SettingsViewModel(
                        services: viewModel.services,
                        onModelChange: { [weak viewModel] model in
                            viewModel?.reloadModel(name: model)
                        }
                    )
                )
            }

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .font(.caption)
    }

    private var stateColor: Color {
        switch viewModel.appState {
        case .idle:
            return .secondary
        case .recording, .streamingRecording:
            return .red
        case .transcribing:
            return .orange
        case .inserting:
            return .blue
        case .error:
            return .red
        }
    }
}
