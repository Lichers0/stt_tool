import SwiftUI

struct MainView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            headerView
            microphonePicker
            lastTranscriptionView
            Divider()
            footerView
        }
        .padding(DS.Spacing.lg)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            HStack(spacing: DS.Spacing.sm) {
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .fill(DS.Colors.primarySubtle)
                    .frame(width: DS.Layout.iconBoxSize, height: DS.Layout.iconBoxSize)
                    .overlay(
                        Image(systemName: "mic.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(DS.Colors.primary)
                    )
                Text("STT Tool")
                    .font(DS.Typography.header)
            }
            Spacer()
            engineBadge
        }
    }

    @ViewBuilder
    private var engineBadge: some View {
        if viewModel.currentEngine == "deepgram" {
            StatusBadge(
                text: "Deepgram",
                foregroundColor: DS.Colors.deepgramBadgeFg,
                backgroundColor: DS.Colors.deepgramBadgeBg
            )
        } else if viewModel.isLoadingModel {
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("Loading...")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
            }
        } else if viewModel.isModelLoaded {
            StatusBadge(
                text: viewModel.services.transcriptionService.currentModelName,
                foregroundColor: DS.Colors.whisperkitBadgeFg,
                backgroundColor: DS.Colors.whisperkitBadgeBg
            )
        } else if let error = viewModel.modelLoadError {
            Text(error)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Colors.destructive)
                .lineLimit(1)
        }
    }

    // MARK: - Microphone Picker

    private var microphonePicker: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "mic.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Picker("", selection: Binding(
                get: { viewModel.services.audioDeviceService.selectedDeviceUID },
                set: { viewModel.services.audioDeviceService.selectDevice(uid: $0) }
            )) {
                Text("System Default")
                    .tag("system-default")
                if !viewModel.services.audioDeviceService.availableDevices.isEmpty {
                    Divider()
                    ForEach(viewModel.services.audioDeviceService.availableDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .padding(.vertical, DS.Spacing.xs)
        .padding(.horizontal, DS.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .fill(DS.Colors.surfaceSubtle)
        )
    }

    // MARK: - Last Transcription

    @ViewBuilder
    private var lastTranscriptionView: some View {
        if let record = viewModel.lastTranscription {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack {
                    Text("LAST TRANSCRIPTION")
                        .font(DS.Typography.tinyLabel)
                        .tracking(0.5)
                        .foregroundStyle(.secondary)
                    Spacer()
                    ActionButton(icon: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(record.text, forType: .string)
                    }
                }

                HStack(alignment: .top, spacing: DS.Spacing.sm) {
                    if let lang = record.language {
                        StatusBadge(text: lang.uppercased())
                    }
                    Text(record.text)
                        .font(.system(size: 12))
                        .lineLimit(4)
                        .textSelection(.enabled)
                        .foregroundStyle(.primary)
                }
            }
            .padding(DS.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .fill(DS.Colors.surfaceSubtle)
            )
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            if viewModel.currentEngine == "deepgram" {
                ActionButton(
                    icon: "character.book.closed",
                    text: "Vocabularies"
                ) {
                    VocabularyManagerWindow.showShared()
                }
            }
            Spacer()
            ActionButton(
                icon: "power",
                text: "Quit",
                destructive: true
            ) {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
