# Audio Device Switching Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add microphone selection with automatic fallback to system default on device disconnect, simplify MainView, and fix tab behavior.

**Architecture:** New `AudioDeviceService` uses CoreAudio C API to enumerate input devices, monitor connect/disconnect events, and persist user selection. `AudioCaptureService` gains a method to set the input device via AudioUnit. `MainView` loses status/record button, gains mic picker. Overlay shows error on device disconnect during recording.

**Tech Stack:** CoreAudio (AudioObjectGetPropertyData, AudioUnit), AVFoundation (AVAudioEngine), SwiftUI (Picker), UserDefaults

---

### Task 1: Create AudioDevice model

**Files:**
- Create: `STTTool/Models/AudioDevice.swift`

**Step 1: Create the model file**

```swift
import CoreAudio

struct AudioDevice: Identifiable, Equatable, Hashable {
    let id: AudioDeviceID
    let name: String
    let uid: String

    static func == (lhs: AudioDevice, rhs: AudioDevice) -> Bool {
        lhs.uid == rhs.uid
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(uid)
    }
}
```

**Step 2: Verify build**

Run: `xcodebuild -scheme STTTool -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add STTTool/Models/AudioDevice.swift
git commit -m "feat: add AudioDevice model for CoreAudio device representation"
```

---

### Task 2: Create AudioDeviceService

**Files:**
- Create: `STTTool/Services/AudioDeviceService.swift`

**Step 1: Create the service**

```swift
import AVFoundation
import Combine
import CoreAudio

@MainActor
final class AudioDeviceService: ObservableObject {
    @Published private(set) var availableDevices: [AudioDevice] = []
    @Published var selectedDeviceUID: String = "system-default"
    @Published private(set) var activeDevice: AudioDevice?

    private var deviceListListenerId: AudioObjectPropertyListenerBlock?
    private var defaultDeviceListenerId: AudioObjectPropertyListenerBlock?
    private let listenerQueue = DispatchQueue(label: "audio-device-listener")
    private var debounceTask: Task<Void, Never>?

    private let selectedDeviceKey = "selectedAudioDeviceUID"

    init() {
        selectedDeviceUID = UserDefaults.standard.string(forKey: selectedDeviceKey) ?? "system-default"
        refreshDeviceList()
        resolveActiveDevice()
        installListeners()
    }

    deinit {
        removeListeners()
    }

    // MARK: - Public

    func selectDevice(uid: String) {
        selectedDeviceUID = uid
        UserDefaults.standard.set(uid, forKey: selectedDeviceKey)
        resolveActiveDevice()
    }

    /// Returns the AudioDeviceID to use for recording.
    /// Returns nil if "system-default" is selected (AVAudioEngine will use system default).
    var effectiveDeviceID: AudioDeviceID? {
        guard selectedDeviceUID != "system-default" else { return nil }
        if let device = availableDevices.first(where: { $0.uid == selectedDeviceUID }) {
            return device.id
        }
        // Selected device not available — fallback to system default
        return nil
    }

    // MARK: - Device Enumeration

    func refreshDeviceList() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize
        ) == noErr else { return }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize, &deviceIDs
        ) == noErr else { return }

        var inputDevices: [AudioDevice] = []
        for deviceID in deviceIDs {
            guard hasInputStreams(deviceID),
                  let name = deviceName(deviceID),
                  let uid = deviceUID(deviceID) else { continue }
            inputDevices.append(AudioDevice(id: deviceID, name: name, uid: uid))
        }

        availableDevices = inputDevices
    }

    // MARK: - Private Helpers

    private func resolveActiveDevice() {
        if selectedDeviceUID == "system-default" {
            activeDevice = systemDefaultDevice()
        } else if let device = availableDevices.first(where: { $0.uid == selectedDeviceUID }) {
            activeDevice = device
        } else {
            // Selected device not available — fallback
            activeDevice = systemDefaultDevice()
        }
    }

    private func systemDefaultDevice() -> AudioDevice? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize, &deviceID
        ) == noErr, deviceID != kAudioObjectUnknown else { return nil }

        guard let name = deviceName(deviceID),
              let uid = deviceUID(deviceID) else { return nil }
        return AudioDevice(id: deviceID, name: name, uid: uid)
    }

    private func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            deviceID, &propertyAddress, 0, nil, &dataSize
        ) == noErr else { return false }
        return dataSize > 0
    }

    private func deviceName(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(
            deviceID, &propertyAddress, 0, nil, &dataSize, &name
        ) == noErr else { return nil }
        return name as String
    }

    private func deviceUID(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(
            deviceID, &propertyAddress, 0, nil, &dataSize, &uid
        ) == noErr else { return nil }
        return uid as String
    }

    // MARK: - CoreAudio Listeners

    private func installListeners() {
        // Listen for device list changes
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let devicesBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handleDeviceChange()
        }
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress, self.listenerQueue, devicesBlock
        )
        deviceListListenerId = devicesBlock

        // Listen for default input device changes
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let defaultBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handleDeviceChange()
        }
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddress, self.listenerQueue, defaultBlock
        )
        defaultDeviceListenerId = defaultBlock
    }

    private func removeListeners() {
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if let block = deviceListListenerId {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &devicesAddress, listenerQueue, block
            )
        }

        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if let block = defaultDeviceListenerId {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &defaultAddress, listenerQueue, block
            )
        }
    }

    private func handleDeviceChange() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.refreshDeviceList()
            self?.resolveActiveDevice()
        }
    }
}
```

**Step 2: Verify build**

Run: `xcodebuild -scheme STTTool -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add STTTool/Services/AudioDeviceService.swift
git commit -m "feat: add AudioDeviceService with CoreAudio device monitoring"
```

---

### Task 3: Add AudioDeviceService protocol and register in ServiceContainer

**Files:**
- Modify: `STTTool/Services/ServiceContainer.swift`

**Step 1: Add protocol and property**

Add protocol before `ServiceContainer` class:

```swift
@MainActor
protocol AudioDeviceServiceProtocol: AnyObject {
    var availableDevices: [AudioDevice] { get }
    var selectedDeviceUID: String { get set }
    var activeDevice: AudioDevice? { get }
    var effectiveDeviceID: AudioDeviceID? { get }
    func selectDevice(uid: String)
    func refreshDeviceList()
}
```

Add conformance to `AudioDeviceService` (in AudioDeviceService.swift):

```swift
extension AudioDeviceService: AudioDeviceServiceProtocol {}
```

Add to `ServiceContainer`:
- Property: `let audioDeviceService: AudioDeviceServiceProtocol`
- Init parameter: `audioDeviceService: AudioDeviceServiceProtocol? = nil`
- Init body: `self.audioDeviceService = audioDeviceService ?? AudioDeviceService()`

**Step 2: Verify build**

Run: `xcodebuild -scheme STTTool -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add STTTool/Services/ServiceContainer.swift STTTool/Services/AudioDeviceService.swift
git commit -m "feat: register AudioDeviceService in ServiceContainer"
```

---

### Task 4: Add setInputDevice to AudioCaptureService

**Files:**
- Modify: `STTTool/Services/AudioCaptureService.swift`
- Modify: `STTTool/Services/ServiceContainer.swift` (protocol)

**Step 1: Add method to protocol**

In `ServiceContainer.swift`, add to `AudioCaptureServiceProtocol`:

```swift
func setInputDevice(_ deviceID: AudioDeviceID?) throws
```

**Step 2: Implement in AudioCaptureService**

Add `import CoreAudio` at top if not present.

Add method to `AudioCaptureService`:

```swift
func setInputDevice(_ deviceID: AudioDeviceID?) throws {
    guard let deviceID else { return }  // nil = use system default (no-op)

    let inputNode = audioEngine.inputNode
    guard let audioUnit = inputNode.audioUnit else {
        throw AudioCaptureError.deviceError
    }

    var devID = deviceID
    let status = AudioUnitSetProperty(
        audioUnit,
        kAudioOutputUnitProperty_CurrentDevice,
        kAudioUnitScope_Global,
        0,
        &devID,
        UInt32(MemoryLayout<AudioDeviceID>.size)
    )

    guard status == noErr else {
        throw AudioCaptureError.deviceError
    }
}
```

Add `.deviceError` case to `AudioCaptureError`:

```swift
case deviceError
```

With description:

```swift
case .deviceError:
    return "Failed to set audio input device"
```

**Step 3: Verify build**

Run: `xcodebuild -scheme STTTool -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add STTTool/Services/AudioCaptureService.swift STTTool/Services/ServiceContainer.swift
git commit -m "feat: add setInputDevice to AudioCaptureService"
```

---

### Task 5: Add device disconnect handling to AudioCaptureService

**Files:**
- Modify: `STTTool/Services/AudioCaptureService.swift`
- Modify: `STTTool/Services/ServiceContainer.swift` (protocol)

**Step 1: Add onDeviceDisconnected callback to protocol**

In `AudioCaptureServiceProtocol`:

```swift
var onDeviceDisconnected: (() -> Void)? { get set }
```

**Step 2: Implement in AudioCaptureService**

Add property:

```swift
var onDeviceDisconnected: (() -> Void)?
```

Add observer setup in a new private method `observeConfigurationChanges()`:

```swift
private var configObserver: NSObjectProtocol?

private func observeConfigurationChanges() {
    configObserver = NotificationCenter.default.addObserver(
        forName: .AVAudioEngineConfigurationChange,
        object: audioEngine,
        queue: .main
    ) { [weak self] _ in
        guard let self, self.isRecording else { return }
        print("[AudioCapture] Engine configuration changed — device likely disconnected")
        self.forceStop()
        self.onDeviceDisconnected?()
    }
}

private func forceStop() {
    guard isRecording else { return }
    audioEngine.inputNode.removeTap(onBus: 0)
    audioEngine.stop()
    isRecording = false

    lock.lock()
    samples.removeAll()
    lock.unlock()

    chunkCallback = nil
    isStreamingMode = false
    bufferLock.lock()
    isBuffering = false
    audioBuffer.removeAll()
    drainSemaphore = nil
    bufferLock.unlock()
}
```

Call `observeConfigurationChanges()` at the end of `init()` (add an `init()` method if none exists):

```swift
init() {
    observeConfigurationChanges()
}
```

Remove observer in `deinit`:

```swift
deinit {
    if let observer = configObserver {
        NotificationCenter.default.removeObserver(observer)
    }
}
```

**Step 3: Verify build**

Run: `xcodebuild -scheme STTTool -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add STTTool/Services/AudioCaptureService.swift STTTool/Services/ServiceContainer.swift
git commit -m "feat: handle AVAudioEngine configuration change on device disconnect"
```

---

### Task 6: Wire device selection into MenuBarViewModel

**Files:**
- Modify: `STTTool/ViewModels/MenuBarViewModel.swift`

**Step 1: Set input device before starting recording**

In `startWhisperKitRecording()`, before `try services.audioCaptureService.startRecording()`:

```swift
try services.audioCaptureService.setInputDevice(services.audioDeviceService.effectiveDeviceID)
```

In `startDeepgramStreaming()`, before `try services.audioCaptureService.startStreaming`:

```swift
try services.audioCaptureService.setInputDevice(services.audioDeviceService.effectiveDeviceID)
```

In `startDeepgramREST()`, before `try services.audioCaptureService.startStreaming`:

```swift
try services.audioCaptureService.setInputDevice(services.audioDeviceService.effectiveDeviceID)
```

**Step 2: Subscribe to device disconnect**

In `activate()`, add:

```swift
setupDeviceDisconnectHandler()
```

Add new method:

```swift
private func setupDeviceDisconnectHandler() {
    services.audioCaptureService.onDeviceDisconnected = { [weak self] in
        Task { @MainActor in
            self?.handleDeviceDisconnect()
        }
    }
}

private func handleDeviceDisconnect() {
    guard appState == .recording || appState == .streamingRecording else { return }

    stopRecordingTimer()
    unregisterOverlayHotkeys()
    unregisterEditHotkeys()
    services.hotKeyService.unregisterModeToggle()
    services.hotKeyService.unregisterCancel()

    if appState == .streamingRecording {
        let mode = UserDefaults.standard.string(forKey: Constants.deepgramModeKey) ?? Constants.defaultDeepgramMode
        if mode == "streaming" {
            nonisolated(unsafe) let deepgram = services.deepgramService
            deepgram.cancelStreaming()
        }
    }
    // AudioCaptureService already stopped by forceStop()

    overlay.showError("Microphone disconnected")
    appState = .idle
    print("[DeviceDisconnect] Recording stopped, mic disconnected")
}
```

**Step 3: Verify build**

Run: `xcodebuild -scheme STTTool -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add STTTool/ViewModels/MenuBarViewModel.swift
git commit -m "feat: wire device selection and disconnect handling into MenuBarViewModel"
```

---

### Task 7: Add showError method to FloatingOverlayWindow

**Files:**
- Modify: `STTTool/Views/FloatingOverlayWindow.swift`

**Step 1: Add error state to OverlayViewModel**

Add published property:

```swift
@Published var errorMessage: String?
```

In `reset()`, add:

```swift
errorMessage = nil
```

**Step 2: Add showError to FloatingOverlayWindow**

```swift
func showError(_ message: String) {
    overlayViewModel.reset()
    overlayViewModel.errorMessage = message
    overlayViewModel.isConnecting = false

    // Position and show
    positionOnScreen(of: nil)
    alphaValue = 0
    orderFrontRegardless()
    NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.15
        self.animator().alphaValue = 1
    }

    // Auto-dismiss after 2 seconds
    Task { @MainActor in
        try? await Task.sleep(for: .seconds(2))
        self.dismissAnimated()
    }
}
```

**Step 3: Add error display to OverlayContentView**

In the OverlayContentView body, add a conditional view for `errorMessage`. When `viewModel.errorMessage != nil`, show centered red text with the error message instead of the normal recording UI.

Look at the existing OverlayContentView layout and add at the top of the body:

```swift
if let error = viewModel.errorMessage {
    HStack(spacing: 8) {
        Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
        Text(error)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color(red: 1.0, green: 0.7, blue: 0.7))
    }
    .padding()
} else {
    // ... existing content
}
```

**Step 4: Verify build**

Run: `xcodebuild -scheme STTTool -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add STTTool/Views/FloatingOverlayWindow.swift
git commit -m "feat: add error display to overlay for device disconnect"
```

---

### Task 8: Add microphone picker to MainView and remove status/record button

**Files:**
- Modify: `STTTool/Views/MainView.swift`

**Step 1: Remove statusView and RecordButton from body**

Replace the body with:

```swift
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
```

**Step 2: Add microphonePicker view**

```swift
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
```

**Step 3: Verify build**

Run: `xcodebuild -scheme STTTool -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add STTTool/Views/MainView.swift
git commit -m "feat: add mic picker to MainView, remove status and record button"
```

---

### Task 9: Fix tab reset and hit area in MenuBarPopoverView

**Files:**
- Modify: `STTTool/Views/MenuBarPopoverView.swift`

**Step 1: Reset activeTab to .main on popover appear**

Add `.onAppear` modifier to the outermost `VStack` in `body`:

```swift
.onAppear {
    activeTab = .main
}
```

Note: `MenuBarExtra` with `.window` style recreates the view each time it opens, so `onAppear` fires each time. But adding explicit reset ensures correctness even if SwiftUI caches the view.

**Step 2: Fix tab hit area**

In the `tabBar` view, add `.contentShape(Rectangle())` to the button's label, after `.foregroundStyle(...)`:

```swift
.contentShape(Rectangle())
```

This makes the entire tab area clickable, not just the text label.

**Step 3: Verify build**

Run: `xcodebuild -scheme STTTool -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add STTTool/Views/MenuBarPopoverView.swift
git commit -m "fix: reset tab to Main on popover open, fix tab hit area"
```

---

### Task 10: Verify and cleanup

**Step 1: Full build verification**

Run: `xcodebuild -scheme STTTool -destination 'platform=macOS' build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

**Step 2: Check for unused imports/references**

- Verify `RecordButton` and `StatusIndicator` are still used elsewhere (e.g., by other views). If `RecordButton` is only used in `MainView`, leave the file — it may be used in future or removed separately.
- Check no compiler warnings related to the changes.

**Step 3: Final commit (if any cleanup needed)**

```bash
git add -A
git commit -m "chore: cleanup after audio device switching implementation"
```

---

### Task 11: Manual testing checklist

These tests must be performed manually on a real macOS machine:

1. **Launch app** — mic picker shows "System Default" in MainView
2. **Open popover** — always opens on Main tab
3. **Tab clicking** — clicking anywhere on tab area (not just text) switches tabs
4. **Mic picker** — shows all available input devices
5. **Select specific mic** — start recording, verify it uses selected device
6. **Disconnect mic during recording** — verify recording stops, overlay shows "Microphone disconnected" error for 2 seconds
7. **Start new recording after disconnect** — verify it uses system default
8. **Reconnect mic** — verify it appears in picker, can be selected again
9. **Persistence** — select a mic, quit app, relaunch — selected mic should be restored
10. **No mics scenario** — (if testable) verify graceful behavior
