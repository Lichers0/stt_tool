import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var permissionsService: PermissionsServiceProtocol

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        self._permissionsService = State(initialValue: viewModel.permissionsService)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.headline)

            engineSection
            Divider()
            if viewModel.selectedEngine == "deepgram" {
                vocabularySection
                Divider()
            }
            if viewModel.selectedEngine == "whisperkit" {
                modelSection
                Divider()
            }
            permissionsSection
            Divider()
            hotkeySection
        }
        .padding(16)
        .frame(width: 340)
    }

    // MARK: - Engine Section

    private var engineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcription Engine")
                .font(.subheadline)
                .fontWeight(.medium)

            Picker("", selection: $viewModel.selectedEngine) {
                Text("Deepgram (online)").tag("deepgram")
                Text("WhisperKit (offline)").tag("whisperkit")
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.selectedEngine) { _, newValue in
                viewModel.setEngine(newValue)
            }

            if viewModel.selectedEngine == "deepgram" {
                deepgramSettingsSection
            }
        }
    }

    private var deepgramSettingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Mode:", selection: $viewModel.deepgramMode) {
                Text("Streaming").tag("streaming")
                Text("REST").tag("rest")
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.deepgramMode) { _, newValue in
                viewModel.setDeepgramMode(newValue)
            }

            apiKeySection
        }
    }

    // MARK: - API Key Section

    @State private var newAPIKey = ""
    @State private var isEditingKey = false

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("API Key")
                .font(.caption)
                .foregroundStyle(.secondary)

            if viewModel.hasAPIKey && !isEditingKey {
                HStack {
                    Text("............")
                        .font(.caption)
                    Spacer()
                    Button("Change") { isEditingKey = true }
                        .font(.caption).controlSize(.small)
                    Button("Delete") { viewModel.deleteAPIKey() }
                        .font(.caption).controlSize(.small)
                        .foregroundStyle(.red)
                }
            } else {
                HStack {
                    SecureField("Deepgram API Key", text: $newAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    Button(viewModel.isValidatingKey ? "..." : "Save") {
                        Task {
                            await viewModel.saveAPIKey(newAPIKey)
                            newAPIKey = ""
                            isEditingKey = false
                        }
                    }
                    .font(.caption).controlSize(.small)
                    .disabled(newAPIKey.isEmpty || viewModel.isValidatingKey)
                    if isEditingKey {
                        Button("Cancel") { isEditingKey = false; newAPIKey = "" }
                            .font(.caption).controlSize(.small)
                    }
                }
                if let error = viewModel.apiKeyError {
                    Text(error).font(.caption2).foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - Vocabulary Section

    private var vocabularySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Vocabulary")
                .font(.subheadline)
                .fontWeight(.medium)

            Button("Manage Vocabularies...") {
                VocabularyManagerWindow.showShared()
            }
            .font(.caption)

            Text("Create themed vocabularies to improve recognition of specific terms.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Model Section

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Whisper Model")
                .font(.subheadline)
                .fontWeight(.medium)

            ForEach(viewModel.availableModels, id: \.self) { model in
                Button(action: { viewModel.selectModel(model) }) {
                    HStack {
                        Image(systemName: model == viewModel.selectedModel
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(model == viewModel.selectedModel ? .blue : .secondary)
                        VStack(alignment: .leading) {
                            Text(viewModel.modelDescriptions[model] ?? model)
                                .font(.caption)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Permissions Section

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Permissions")
                .font(.subheadline)
                .fontWeight(.medium)

            permissionRow(
                title: "Microphone",
                granted: permissionsService.isMicrophoneGranted,
                action: {
                    Task {
                        _ = await permissionsService.requestMicrophoneAccess()
                    }
                }
            )

            permissionRow(
                title: "Accessibility",
                granted: permissionsService.isAccessibilityGranted,
                action: {
                    permissionsService.openAccessibilitySettings()
                }
            )

            Button("Refresh") {
                permissionsService.checkPermissions()
            }
            .font(.caption)
        }
    }

    private func permissionRow(
        title: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(granted ? .green : .red)
            Text(title)
                .font(.caption)
            Spacer()
            if !granted {
                Button("Grant", action: action)
                    .font(.caption)
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Hotkey Section

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hotkey")
                .font(.subheadline)
                .fontWeight(.medium)

            HotKeyRecorderView(viewModel: viewModel)

            HStack {
                Text("Mode Toggle:")
                    .font(.caption)
                Text(viewModel.modeToggleKeyDisplayString)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .quaternarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }
}

// MARK: - Hotkey Recorder

private struct HotKeyRecorderView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggleRecording) {
                Text(isRecording ? "Type shortcut..." : viewModel.hotKeyDisplayString)
                    .font(.caption)
                    .frame(minWidth: 120)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isRecording
                                ? Color.accentColor.opacity(0.15)
                                : Color(nsColor: .quaternarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isRecording ? Color.accentColor : .clear, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            if !isRecording {
                Button("Reset") {
                    viewModel.resetHotKey()
                }
                .font(.caption)
                .controlSize(.small)
            }
        }
        .onDisappear { stopRecording() }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        viewModel.suspendHotKey()

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape cancels recording
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }

            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .subtracting(.capsLock)

            // Require at least one modifier key
            let requiredMods: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
            guard !mods.intersection(requiredMods).isEmpty else { return nil }

            viewModel.hotKeyKeyCode = UInt32(event.keyCode)
            viewModel.hotKeyModifiers = UInt32(mods.rawValue)
            viewModel.saveHotKey()
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        viewModel.resumeHotKey()
    }
}
