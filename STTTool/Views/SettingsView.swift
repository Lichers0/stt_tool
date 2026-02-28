import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var permissionsService: PermissionsServiceProtocol
    @State private var activeSubTab = "general"

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        self._permissionsService = State(initialValue: viewModel.permissionsService)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            // Header + sub-tabs
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                Text("Settings")
                    .font(DS.Typography.header)

                SegmentedPicker(
                    items: [
                        ("General", "general"),
                        ("Engine", "engine"),
                        ("Permissions", "permissions")
                    ],
                    selection: $activeSubTab
                )
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.lg)

            // Content
            ScrollView {
                switch activeSubTab {
                case "general":
                    generalTab
                case "engine":
                    engineTab
                case "permissions":
                    permissionsTab
                default:
                    EmptyView()
                }
            }
            .frame(maxHeight: 360)
        }
        .padding(.bottom, DS.Spacing.lg)
    }

    // MARK: - General Tab

    @State private var shortcutsExpanded = false

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            // Sound toggle
            HStack {
                Text("Sound")
                    .font(DS.Typography.caption)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { viewModel.soundMode == "on" },
                    set: { viewModel.setSoundMode($0 ? "on" : "off") }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }

            // Check for Updates
            HStack {
                Text("Check for Updates")
                    .font(DS.Typography.caption)
                Spacer()
                Button("Check") {
                    viewModel.checkForUpdates()
                }
                .controlSize(.small)
                .disabled(!viewModel.canCheckForUpdates)
            }

            Divider()

            // Keyboard Shortcuts
            DisclosureGroup(isExpanded: $shortcutsExpanded) {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    // Record Toggle
                    HStack {
                        shortcutLabel("Record Toggle")
                        Spacer()
                        HotKeyRecorderView(viewModel: viewModel)
                    }

                    // Cancel Recording
                    HStack {
                        shortcutLabel("Cancel Recording")
                        Spacer()
                        CancelKeyRecorderView(viewModel: viewModel)
                    }

                    // Mode Toggle Key
                    HStack {
                        shortcutLabel("Mode Toggle")
                        Spacer()
                        kbdBadge(viewModel.modeToggleKeyDisplayString)
                    }

                    // Vocabulary Switching (read-only)
                    HStack {
                        shortcutLabel("Vocab Switch")
                        Spacer()
                        HStack(spacing: DS.Spacing.xs) {
                            kbdBadge("←")
                            kbdBadge("→")
                            Text("+")
                                .font(DS.Typography.tinyLabel)
                                .foregroundStyle(.secondary)
                            kbdBadge("Enter")
                        }
                    }
                }
                .padding(.top, DS.Spacing.sm)
            } label: {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("Keyboard Shortcuts")
                }
            }
            .font(DS.Typography.caption)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.xs)
    }

    // MARK: - Engine Tab

    private var engineTab: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xl) {
            // Engine picker
            sectionLabel("TRANSCRIPTION ENGINE")
            SegmentedPicker(
                items: [
                    ("Deepgram", "deepgram"),
                    ("WhisperKit", "whisperkit")
                ],
                selection: $viewModel.selectedEngine
            )
            .onChange(of: viewModel.selectedEngine) { _, newValue in
                viewModel.setEngine(newValue)
            }

            if viewModel.selectedEngine == "deepgram" {
                Divider()
                deepgramSettings
            }

            if viewModel.selectedEngine == "whisperkit" {
                Divider()
                whisperSettings
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.xs)
    }

    private var deepgramSettings: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xl) {
            // Mode
            sectionLabel("MODE")
            SegmentedPicker(
                items: [("Streaming", "streaming"), ("REST", "rest")],
                selection: $viewModel.deepgramMode
            )
            .onChange(of: viewModel.deepgramMode) { _, newValue in
                viewModel.setDeepgramMode(newValue)
            }

            Divider()

            // API Key
            sectionLabel("API KEY")
            apiKeySection

            Divider()

            // Vocabulary
            sectionLabel("VOCABULARY")
            ActionButton(
                icon: "character.book.closed",
                text: "Manage Vocabularies...",
                style: .outline
            ) {
                VocabularyManagerWindow.showShared()
            }
            Text("Create themed vocabularies to improve recognition accuracy for specialized terms.")
                .font(DS.Typography.tinyLabel)
                .foregroundStyle(.secondary)
        }
    }

    private var whisperSettings: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            sectionLabel("MODEL")
            ForEach(viewModel.availableModels, id: \.self) { model in
                Button(action: { viewModel.selectModel(model) }) {
                    HStack {
                        Image(systemName: model == viewModel.selectedModel
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(model == viewModel.selectedModel
                                             ? DS.Colors.primary : .secondary)
                            .font(.system(size: 14))
                        Text(viewModel.modelDescriptions[model] ?? model)
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, DS.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.lg)
                            .fill(model == viewModel.selectedModel
                                  ? DS.Colors.primary.opacity(0.05)
                                  : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - API Key Section

    @State private var newAPIKey = ""
    @State private var isEditingKey = false

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            if viewModel.hasAPIKey && !isEditingKey {
                HStack {
                    Text("............")
                        .font(DS.Typography.monoCaption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.md)
                                .fill(DS.Colors.surfaceSubtle)
                        )
                    ActionButton(
                        icon: "pencil",
                        text: "Change",
                        style: .outline
                    ) {
                        isEditingKey = true
                    }
                }
            } else {
                HStack {
                    SecureField("Enter API key...", text: $newAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .font(DS.Typography.caption)
                    Button(viewModel.isValidatingKey ? "..." : "Save") {
                        Task {
                            await viewModel.saveAPIKey(newAPIKey)
                            newAPIKey = ""
                            isEditingKey = false
                        }
                    }
                    .controlSize(.small)
                    .disabled(newAPIKey.isEmpty || viewModel.isValidatingKey)
                    if isEditingKey {
                        Button("Cancel") { isEditingKey = false; newAPIKey = "" }
                            .controlSize(.small)
                    }
                }
                if let error = viewModel.apiKeyError {
                    Text(error)
                        .font(DS.Typography.tinyLabel)
                        .foregroundStyle(DS.Colors.destructive)
                }
            }
        }
    }

    // MARK: - Permissions Tab

    private var permissionsTab: some View {
        VStack(spacing: DS.Spacing.md) {
            permissionRow(
                id: "microphone",
                label: "Microphone",
                granted: permissionsService.isMicrophoneGranted,
                grantAction: {
                    Task { _ = await permissionsService.requestMicrophoneAccess() }
                },
                grantLabel: "Grant"
            )

            permissionRow(
                id: "accessibility",
                label: "Accessibility",
                granted: permissionsService.isAccessibilityGranted,
                grantAction: { permissionsService.openAccessibilitySettings() },
                grantLabel: "Open Settings"
            )

            ActionButton(
                icon: "arrow.clockwise",
                text: "Refresh Status"
            ) {
                permissionsService.checkPermissions()
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.xs)
    }

    private func permissionRow(
        id: String,
        label: String,
        granted: Bool,
        grantAction: @escaping () -> Void,
        grantLabel: String
    ) -> some View {
        HStack {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(granted ? .green : .red)
                    .font(.system(size: 14))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            Spacer()
            if !granted {
                Button(grantLabel, action: grantAction)
                    .controlSize(.small)
            }
        }
        .padding(DS.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .fill(granted ? DS.Colors.grantedBg : DS.Colors.deniedBg)
        )
    }

    // MARK: - Helpers

    private func shortcutLabel(_ text: String) -> some View {
        Text(text)
            .font(DS.Typography.caption)
            .foregroundStyle(.primary)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(DS.Typography.tinyLabel)
            .tracking(0.5)
            .foregroundStyle(.secondary)
    }

    private func kbdBadge(_ text: String) -> some View {
        Text(text)
            .font(DS.Typography.monoCaption)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xs)
            .background(DS.Colors.surfaceSubtle)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
    }
}

// MARK: - Hotkey Recorder

private struct HotKeyRecorderView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Button(action: toggleRecording) {
                Text(isRecording ? "Type shortcut..." : viewModel.hotKeyDisplayString)
                    .font(DS.Typography.monoCaption)
                    .frame(minWidth: 100)
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, DS.Spacing.xs)
                    .background(isRecording
                                ? DS.Colors.primarySubtle
                                : DS.Colors.surfaceSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.sm)
                            .stroke(isRecording ? DS.Colors.primary : Color(nsColor: .separatorColor),
                                    lineWidth: isRecording ? 1 : 0.5)
                    )
            }
            .buttonStyle(.plain)

            if !isRecording {
                ActionButton(icon: "arrow.counterclockwise") {
                    viewModel.resetHotKey()
                }
            }
        }
        .onDisappear { stopRecording() }
    }

    private func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        isRecording = true
        viewModel.suspendHotKey()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .subtracting(.capsLock)
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

// MARK: - Cancel Key Recorder

private struct CancelKeyRecorderView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Button(action: toggleRecording) {
                Text(isRecording ? "Press a key..." : viewModel.cancelKeyDisplayString)
                    .font(DS.Typography.monoCaption)
                    .frame(minWidth: 100)
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, DS.Spacing.xs)
                    .background(isRecording
                                ? DS.Colors.primarySubtle
                                : DS.Colors.surfaceSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.sm)
                            .stroke(isRecording ? DS.Colors.primary : Color(nsColor: .separatorColor),
                                    lineWidth: isRecording ? 1 : 0.5)
                    )
            }
            .buttonStyle(.plain)

            if !isRecording {
                ActionButton(icon: "arrow.counterclockwise") {
                    viewModel.resetCancelKey()
                }
            }
        }
        .onDisappear { stopRecording() }
    }

    private func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        isRecording = true
        viewModel.suspendHotKey()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            viewModel.cancelKeyCode = UInt32(event.keyCode)
            viewModel.saveCancelKey()
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
