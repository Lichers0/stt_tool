# Audio Device Switching Design

## Problem

When the active audio input device disconnects (e.g., AirPods removed), the app stops working because `AVAudioEngine` loses its input node. There is no device monitoring, no picker UI, and no fallback mechanism.

## Solution

Add microphone selection with automatic fallback to system default on device disconnect.

## Architecture

### New: AudioDeviceService

Responsible for enumerating, monitoring, and selecting audio input devices.

**Model:**

```swift
struct AudioDevice: Identifiable, Equatable {
    let id: AudioDeviceID       // CoreAudio device ID
    let name: String            // Human-readable name
    let uid: String             // Persistent UID for UserDefaults
}
```

**Public API:**

- `@Published var availableDevices: [AudioDevice]` — current input devices
- `@Published var selectedDevice: AudioDevice?` — user's choice (nil = system default)
- `@Published var activeDevice: AudioDevice` — actually used device (with fallback)
- `func selectDevice(_ device: AudioDevice?)` — nil means "System Default"
- `var effectiveDeviceID: AudioDeviceID` — ID to pass to AudioCaptureService

**CoreAudio monitoring:**

- `kAudioHardwarePropertyDevices` listener — updates `availableDevices`
- `kAudioHardwarePropertyDefaultInputDevice` listener — updates `activeDevice` when "System Default" is selected

**Persistence:**

- Store `device.uid` in `UserDefaults` (UID is stable across reboots, unlike AudioDeviceID)
- Value `"system-default"` for the default option

**Debounce:** 0.3s debounce on device list updates (CoreAudio may fire multiple events rapidly).

### Changes: AudioCaptureService

**New method:**

```swift
func setInputDevice(_ deviceID: AudioDeviceID) throws
```

Sets `kAudioOutputUnitProperty_CurrentDevice` on the input node's underlying AudioUnit. Called before `startRecording()`/`startStreaming()`.

**Device disconnect handling:**

Subscribe to `AVAudioEngineConfigurationChange` notification. On trigger:

1. Stop engine (`audioEngine.stop()`, remove tap)
2. Publish `.deviceDisconnected` event via callback

### Changes: MenuBarViewModel

- Subscribe to AudioDeviceService device events
- On device disconnect during recording:
  - Stop streaming/recording
  - AudioDeviceService switches `activeDevice` to default
  - Show "Microphone disconnected" error in overlay (red text)
  - Overlay auto-closes after 2 seconds
- On next hotkey press — recording starts on new `activeDevice`

### Changes: ServiceContainer

- Add `audioDeviceService: AudioDeviceService` property
- Initialize in `ServiceContainer.init()`

## Fallback Logic

1. User selected a specific mic → use it
2. Selected mic disconnected → switch to system default, publish event
3. User selected "System Default" → always follow system default
4. Reconnected mic — do NOT auto-switch back (YAGNI)

## Event Flow: Device Disconnect During Recording

```
CoreAudio → AVAudioEngineConfigurationChange
  → AudioCaptureService.stop()
  → MenuBarViewModel.handleDeviceDisconnect()
    → stop streaming/recording
    → AudioDeviceService switches activeDevice to default
    → OverlayViewModel shows "Microphone disconnected" (red text)
    → overlay auto-closes after 2 seconds
```

## UI Changes

### MainView: Simplified Layout

Remove `statusView` (status indicator) and `RecordButton` from MainView — recording is controlled exclusively via hotkey. New layout:

```
┌─────────────────────────────────┐
│ 🎤 STT Tool          [Deepgram]│  ← header
│                                 │
│  🎙 [System Default        ▾]  │  ← mic picker
│                                 │
│  LAST TRANSCRIPTION        [📋]│  ← last transcription
│  EN  "transcribed text..."     │
│                                 │
│  [📖 Vocabularies]      [Quit] │  ← footer
└─────────────────────────────────┘
```

- SwiftUI `Picker` with `.menu` style — compact dropdown
- Microphone icon + device name
- Options: "System Default" + list of available input devices
- If selected device is unavailable: show "(Unavailable)" suffix, use default

### MenuBarPopoverView: Tab Reset

Reset `activeTab` to `.main` every time the popover opens. Use `onAppear` or `onChange(of: viewModel.isPopoverOpen)`.

### MenuBarPopoverView: Tab Hit Area

Current tab buttons only respond to clicks on the text label. Add `.contentShape(Rectangle())` to make the entire tab area clickable.

## Edge Cases

- **No microphones available:** recording disabled, status shows "No microphone available"
- **Device switch outside recording:** update `activeDevice`, next recording uses it
- **Rapid connect/disconnect:** debounce 0.3s on device list updates
- **First launch:** `selectedDevice = nil` (system default), nothing in UserDefaults

## Out of Scope (YAGNI)

- Input level indicator
- Microphone test from UI
- Auto-return to previously selected mic on reconnect
- Multiple microphone selection
