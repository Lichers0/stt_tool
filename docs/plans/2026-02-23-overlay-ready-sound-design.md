# Overlay Ready Sound & Visual Indicator

**Date:** 2026-02-23
**Status:** Approved

## Problem

When the floating overlay opens on hotkey press, the "ready" sound doesn't play at all.
The overlay appears before WebSocket is connected, giving no feedback about readiness.

## Solution

### New Flow (Deepgram Streaming)

1. Hotkey pressed
2. Overlay appears **immediately** with **pulsing yellow dot** and "Listening..." text (no timer)
3. WebSocket: if already `.ready`/`.idle` — skip connect; if `.disconnected` — connect
4. Once WebSocket ready + audio capture started:
   - Dot → **solid green**
   - Play **`recordStart`** sound
   - **Timer starts** (reflects real recording duration)
5. User speaks, sees interim/final text
6. Hotkey pressed again → recording stops
7. Text processed and inserted → play **`recordStop`** sound

### Sound System Simplification

- Remove `"default"` mode (system sounds Tink/Pop)
- Two modes only: **"on"** (custom bundled sounds) and **"off"** (silent)
- `playStartSound()`: plays `recordStart` if soundMode != "off"
- `playStopSound()`: plays `recordStop` if soundMode != "off"
- Remove `NSSound.tink`, `NSSound.pop` helpers
- Keep `NSSound.basso` for error feedback only

### Visual Indicator

- New **colored dot** in overlay header, before the mode badge `[A]`
- **Yellow pulsing** — WebSocket connecting / not ready
- **Green solid** — WebSocket ready, recording active

### Code Changes

**OverlayViewModel:**
- Add `@Published var isConnecting = true`
- `reset()` sets `isConnecting = true`

**OverlayContentView:**
- Add dot indicator before mode badge in header HStack
- Yellow pulsing animation when `isConnecting == true`
- Green solid when `isConnecting == false`

**FloatingOverlayWindow:**
- Add `setConnecting(_ connecting: Bool)` method

**MenuBarViewModel.startDeepgramStreaming():**
1. Overlay already shown (from `startDeepgramRecording`)
2. `isConnecting = true` (default from reset)
3. WebSocket connect (if needed)
4. `startStreaming()` + `startAudioCapture()`
5. `overlay.setConnecting(false)` — dot turns green
6. `playStartSound()` — ready sound
7. `startRecordingTimer()` — **moved here** from `startDeepgramRecording`

**MenuBarViewModel.startDeepgramRecording():**
- Remove `startRecordingTimer()` call (moved to after ready)

**Settings:**
- Sound Picker: "on" / "off" (remove "default")
- Update `soundMode` default from `"default"` to `"on"`

### Edge Cases

| Scenario | Behavior |
|----------|----------|
| WebSocket already idle | Dot turns green instantly + sound |
| WebSocket connect fails | Dot stays yellow, overlay dismissed, error shown |
| Deepgram REST mode | No WebSocket needed, `isConnecting = false` immediately |
| WhisperKit mode | No overlay, sound plays at recording start |
| Vocabulary switch (reconnect) | Existing `isReconnecting` blink stays; dot may pulse yellow during reconnect |

### Files to Modify

1. `STTTool/Views/FloatingOverlayWindow.swift` — ViewModel + View + new method
2. `STTTool/ViewModels/MenuBarViewModel.swift` — flow reorder, sound simplification
3. `STTTool/Views/SettingsView.swift` — sound picker options
4. `STTTool/ViewModels/SettingsViewModel.swift` — sound mode default
5. `STTTool/Utilities/Constants.swift` — update soundMode default if needed
