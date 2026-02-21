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

            modelSection
            Divider()
            permissionsSection
            Divider()
            hotkeySection
        }
        .padding(16)
        .frame(width: 340)
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
