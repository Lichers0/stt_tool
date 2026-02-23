# Permissions Window Design

**Status:** Approved
**Date:** 2026-02-23

## Problem

1. At startup, no indication of missing permissions — hotkeys don't work, no UI shown
2. Clicking menu bar icon triggers keychain password dialog without context
3. After granting Accessibility in System Settings, unclear when app detects it
4. Have to close/reopen popover to see updated permission status

## Solution

Replace in-popover StartupGuardianView with a standalone NSWindow that opens automatically at launch when permissions are missing.

## Flow

1. App launch → `checkPermissions()`
2. All permissions granted → `activate()`, normal operation
3. Something missing → show standalone **PermissionsWindow**
4. Menu bar icon click while window open → focus the window (no popover)
5. All permissions granted → user clicks "Continue" → window closes, `activate()`, popover works normally

Permissions are checked every launch. No "first run" flags — pure state check.

## Window UI

NSWindow, ~400x350, centered, non-resizable, title "STT Tool Setup".

Three permission rows:

```
┌─────────────────────────────────────────┐
│           STT Tool Setup                │
│                                         │
│  Microphone                  ✅ Granted │
│                                         │
│  Accessibility        [Open Settings]   │
│     ⏳ Waiting for permission...        │
│                                         │
│  API Key Storage      [Allow Access]    │
│     Unlock keychain for Deepgram key    │
│                                         │
│              [Continue]  (disabled)      │
└─────────────────────────────────────────┘
```

Row states:
- **Not granted:** action button + description of why needed
- **Waiting (Accessibility only):** spinner + "Waiting for permission..." after clicking "Open Settings", polling every 2 sec
- **Granted:** green checkmark, button disappears

"Continue" button: disabled until Microphone + Accessibility granted. Keychain is optional (WhisperKit users don't need API key).

## Permission Behavior

### Microphone
- Click → `AVCaptureDevice.requestAccess()` → system dialog
- Status updates instantly after user response
- If denied → text "Open System Settings → Privacy → Microphone" + "Open Settings" button

### Accessibility
- "Open Settings" → opens System Settings > Accessibility
- After click: button replaced with spinner + "Waiting for permission..."
- Polling `AXIsProcessTrusted()` every 2 sec while window is open
- Once granted → spinner replaced with checkmark (animated)
- Polling stops after permission obtained

### Keychain
- "Allow Access" button with explanation: "Allow Keychain access to store Deepgram API key"
- Click → `probeKeychainAccess()` → system password dialog
- Results: granted / denied / notConfigured
- **notConfigured** (no key yet) → gray text "Not configured yet", does not block Continue
- **denied** → error text + retry button

## Edge Cases

- **User tries to close window:** window is not closable (no close button). Only exit: "Continue" or Quit app via menu bar icon.
- **Permission revoked during runtime:** no change — current behavior (error on record attempt) is sufficient for this rare case.
- **Keychain "Allow Once" vs "Always Allow":** if user chose "Allow Once", next launch shows "Allow Access" again. Expected behavior.
- **Window hidden behind other windows:** menu bar icon click → `window.makeKeyAndOrderFront()`.

## Implementation

### New files
- `STTTool/Views/PermissionsWindow.swift` — SwiftUI view + NSWindow wrapper

### Modified files
1. **`STTToolApp.swift`** — open PermissionsWindow instead of in-popover guard; menu bar click focuses window when open; remove `permissionsReady` logic from MenuBarExtra body
2. **`PermissionsService.swift`** — polling tied to window lifecycle; add `checkAllAndReport()` method
3. **`MenuBarViewModel.swift`** — remove duplicate permission checks

### Deleted files
- `StartupGuardianView.swift` — replaced by PermissionsWindow

### Unchanged
- KeychainService, HotKeyService, KeyInterceptor, DesignSystem — no changes
