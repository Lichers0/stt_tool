# STT Tool — Interface Documentation

## Overview

STT Tool is a macOS MenuBar application for speech-to-text transcription. The app lives in the system menu bar and provides a popover-based UI with additional windows for vocabulary management and a floating overlay during recording.

**Engines supported:** Deepgram (online) and WhisperKit (offline).

---

## Architecture

```
MenuBar Icon (mic)
│
├─ Click → Popover
│  ├─ Main View (recording controls, status)
│  ├─ History (popover within popover)
│  ├─ Settings (popover within popover)
│  └─ Vocabulary Manager (separate window, Deepgram only)
│
└─ During streaming recording → Floating Overlay (separate panel)
```

---

## 1. Menu Bar Icon

**Location:** macOS system menu bar (top-right area).

The icon changes dynamically based on app state:

| State | Icon | Description |
|-------|------|-------------|
| Idle | `mic` | Microphone outline — ready |
| Recording | `mic.fill` | Filled microphone — recording active |
| Transcribing | `text.bubble` | Speech bubble — processing audio |
| Inserting | `doc.on.clipboard` | Clipboard — pasting text |
| Error | `exclamationmark.triangle` | Warning — something went wrong |

**Interaction:** Left-click opens the main popover.

---

## 2. Startup Permissions Screen

**Displayed when:** Required permissions are not yet granted (first launch or revoked).
**Size:** 360px wide.
**Replaces:** the main popover content inside the MenuBar window.

### Layout

```
┌─────────────────────────────────┐
│     🎙 (mic.and.signal.meter)   │
│        STT Tool Setup           │
│  Grant permissions to enable    │
│       voice transcription.      │
│                                 │
│  ● Step 1: Microphone           │
│    Required to record speech.   │
│    [Grant Access]               │
│                                 │
│  ● Step 2: Accessibility        │
│    Required to paste text       │
│    into other apps.             │
│    [Open Settings]              │
│    (helper text shown below)    │
│                                 │
│  ● Step 3: Keychain             │
│    Secure storage for API keys. │
│    [Retry] (if denied)          │
│                                 │
│         [Continue]              │
│    (disabled until Step 1 & 2   │
│     are granted)                │
└─────────────────────────────────┘
```

### Permission Rows

Each row displays:
- **Step number** and **icon** (orange if pending, green if granted)
- **Title** and **description**
- **Action button** (context-dependent)

| Permission | Icon | Action Button | Behavior |
|-----------|------|---------------|----------|
| Microphone | `mic.fill` | "Grant Access" | Triggers system permission dialog |
| Accessibility | `accessibility` | "Open Settings" | Opens System Settings → Accessibility |
| Keychain | `key.fill` | "Retry" (if denied) | Re-probes keychain access |

**Notes:**
- Accessibility permission is polled automatically while the screen is visible.
- The "Continue" button becomes enabled once Microphone and Accessibility are both granted.
- Keychain status can be: accessible, notConfigured, or denied — description text adjusts accordingly.

---

## 3. Main Popover (MenuBarPopoverView)

**Size:** 320px wide.
**Displayed when:** Permissions are granted and user clicks the menu bar icon.

### Layout

```
┌──────────────────────────────┐
│  🎙 STT Tool    [Deepgram]   │  ← Header + engine badge
│                              │
│      ● Ready                 │  ← Status (icon + text)
│                              │
│   [🎤 Start Recording]      │  ← Main action button
│                              │
│  ┌──────────────────────┐   │
│  │ Last transcription   │   │  ← Last result (if any)
│  │ [en] Some text here  │   │
│  │ that was transcribed  │   │
│  └──────────────────────┘   │
│                              │
│  ─────────────────────────   │  ← Divider
│  🕐    📖    ⚙️    ⏻       │  ← Bottom bar (4 icon buttons)
└──────────────────────────────┘
```

### Header

- **App icon:** `mic.and.signal.meter`
- **Title:** "STT Tool"
- **Engine badge** (right side):
  - Deepgram engine → blue capsule "Deepgram"
  - WhisperKit loading → "Loading model..." + spinner
  - WhisperKit loaded → capsule with model name
  - Error → red error text

### Status View

Displays current app state with icon and text. Colors:

| State | Text | Color | Animation |
|-------|------|-------|-----------|
| Idle | "Ready" | Secondary | — |
| Recording | "Recording..." | Red | Pulse effect |
| Streaming Recording | "Recording (streaming)..." | Red | Pulse effect |
| Transcribing | "Transcribing..." | Orange | — |
| Inserting | "Inserting text..." | Blue | — |
| Error | "Error: {message}" | Red | — |

### Record Button

- **Idle state:** Blue "Start Recording" with `mic.fill` icon
- **Recording state:** Red "Stop Recording" with `stop.fill` icon
- **Disabled when:** transcribing or inserting text
- **Size:** large, full-width

### Last Transcription

Shown only if a previous transcription exists:
- Label "Last transcription" in secondary color
- Language badge (e.g., `[en]`) if detected
- Transcription text (up to 4 lines, selectable)
- Background: `ultraThinMaterial` rounded rectangle

### Bottom Bar

Four icon-only buttons arranged horizontally:

| # | Icon | Name | Action |
|---|------|------|--------|
| 1 | `clock.arrow.circlepath` | History | Opens History popover |
| 2 | `character.book.closed` | Vocabularies | Opens Vocabulary Manager window (Deepgram only) |
| 3 | `gearshape` | Settings | Opens Settings popover |
| 4 | `power` | Quit | Terminates the application |

---

## 4. History View

**Type:** Popover (opens from History button in main view).
**Size:** 360px wide × 400px tall.

### Layout

```
┌─────────────────────────────────┐
│  History              [Clear All]│
│  ─────────────────────────────  │
│                                  │
│  "Some transcribed text that    │
│   was spoken earlier..."         │
│   [en]  2 min ago  large-v3     │
│                           [📋]  │
│  ─────────────────────────────  │
│  "Another transcription..."     │
│   [ru]  1 hour ago  Deepgram    │
│                           [📋]  │
│  ─────────────────────────────  │
│  ...                            │
│                                  │
└─────────────────────────────────┘
```

### Header
- Title: "History"
- "Clear All" button (red text, visible only when records exist)

### Empty State
- Icon: `text.bubble` (secondary)
- Text: "No transcriptions yet"

### Record Row

Each history entry displays:
- **Transcription text** (up to 3 lines)
- **Language badge** (if detected)
- **Relative date** (e.g., "2 min ago")
- **Model name** (e.g., "large-v3", "Deepgram")
- **Copy button** (`doc.on.doc`) — copies text to clipboard

### Interactions
- **Swipe left** on a row to delete it
- **Copy button** copies the transcription text
- **Clear All** removes all records

---

## 5. Settings View

**Type:** Popover (opens from Settings button in main view).
**Size:** 340px wide, scrollable.

### Layout

```
┌──────────────────────────────────┐
│  Settings                        │
│                                  │
│  TRANSCRIPTION ENGINE            │
│  [Deepgram (online)|WhisperKit]  │  ← Segmented picker
│                                  │
│  ┌─ Deepgram Settings ────────┐ │
│  │ Mode: [Streaming | REST]   │ │  ← Segmented picker
│  │                            │ │
│  │ API Key                    │ │
│  │ ............  [Change][Del]│ │  ← If key exists
│  │  — or —                    │ │
│  │ [••••••••••] [Save]        │ │  ← If no key / editing
│  └────────────────────────────┘ │
│  ─────────────────────────────── │
│  VOCABULARY                      │
│  [Manage Vocabularies...]        │
│  Create themed vocabularies...   │
│  ─────────────────────────────── │
│  WHISPER MODEL (if WhisperKit)   │
│  ○ tiny                          │
│  ○ base                          │
│  ● small  ← selected            │
│  ○ medium                        │
│  ○ large-v3                      │
│  ○ large-v3_turbo                │
│  ─────────────────────────────── │
│  PERMISSIONS                     │
│  ✅ Microphone                   │
│  ✅ Accessibility                │
│  ❌ ... [Grant]                  │
│               [Refresh]          │
│  ─────────────────────────────── │
│  HOTKEY                          │
│  [⌘⇧Space      ]  [Reset]       │
│  Mode Toggle: ↓ (Down Arrow)    │
└──────────────────────────────────┘
```

### Section 1: Transcription Engine

**Segmented Picker** with two options:
- "Deepgram (online)"
- "WhisperKit (offline)"

Changing the engine shows/hides engine-specific sections below.

### Section 2: Deepgram Settings (visible when engine = Deepgram)

**Mode Picker** — segmented:
- "Streaming" — real-time transcription via WebSocket
- "REST" — record first, then send audio

**API Key:**
- If key exists and not editing: masked display (`............`) + "Change" and "Delete" buttons
- If no key or editing: `SecureField` + "Save" button (shows spinner while validating) + "Cancel" (if editing existing key)
- Error text shown below if validation fails

### Section 3: Vocabulary (visible when engine = Deepgram)

- Button: "Manage Vocabularies..." — opens the Vocabulary Manager window
- Helper text explaining the feature

### Section 4: Whisper Model (visible when engine = WhisperKit)

Radio-button list of available models:
- `tiny`, `base`, `small`, `medium`, `large-v3`, `large-v3_turbo`
- Selected model shows `checkmark.circle.fill` (blue)
- Unselected shows `circle` (secondary)

### Section 5: Permissions

Two permission rows:
- **Microphone:** green checkmark if granted, red X + "Grant" button if not
- **Accessibility:** green checkmark if granted, red X + "Grant" button if not
- **Refresh** button to re-check permission status

### Section 6: Hotkey

**HotKeyRecorderView** — interactive keyboard shortcut recorder:
- Click the field to start recording
- Press desired key combination (requires at least one modifier: Cmd/Shift/Opt/Ctrl)
- Displays current shortcut (e.g., "⌘⇧Space")
- "Reset" button restores defaults
- Escape cancels recording
- Default hotkey: `Cmd+Shift+Space`

**Mode Toggle Key** display:
- Shows the current mode toggle key (default: Down Arrow)
- Read-only display

---

## 6. Vocabulary Manager

**Type:** Separate resizable window (NSWindow).
**Size:** 640px × 460px (min: 500px × 350px).
**Title:** "Vocabulary Manager"
**Visible only when:** Engine is set to Deepgram.

### Layout

```
┌──────────────────────────────────────────────────────┐
│  Vocabulary Manager                          [─][□][×]│
│                                                       │
│  ┌──────────┐  ┌────────────────────────────────────┐│
│  │ SIDEBAR   │  │ DETAIL PANEL                       ││
│  │           │  │                                    ││
│  │ ● General │  │  General                           ││
│  │   Medical │  │                                    ││
│  │   Legal   │  │  [Add term____________] [+]        ││
│  │           │  │                                    ││
│  │           │  │  hello               [×]           ││
│  │           │  │  world               [×]           ││
│  │           │  │  transcription       [×]           ││
│  │           │  │                                    ││
│  │           │  │                                    ││
│  │           │  │                      3 / 100 terms ││
│  │           │  │                                    ││
│  ├──────────┤  └────────────────────────────────────┘│
│  │[+][📋][✏]  [🗑]│                                  │
│  └──────────┘                                        │
│                                                       │
│  Default vocabulary: [Last used | Specific]  [picker] │
└──────────────────────────────────────────────────────┘
```

### Sidebar (left panel, min 180px)

**Vocabulary list:**
- Each row shows vocabulary name and term count
- Blue dot indicator for the currently active vocabulary
- Single-click to select
- Double-click or pencil button to rename (inline TextField)
- Drag-and-drop to reorder

**Sidebar toolbar (bottom):**

| Icon | Action | Notes |
|------|--------|-------|
| `plus` | Create new vocabulary | Creates "New Vocabulary" |
| `doc.on.doc` | Duplicate selected | Copies with "(Copy)" suffix |
| `pencil` | Rename selected | Enables inline editing |
| `trash` | Delete selected | Red, disabled if only 1 vocabulary remains |

### Detail Panel (right panel)

**Header:**
- Vocabulary name (title)
- Selection toolbar (appears in selection mode):
  - Select All / Deselect All
  - Copy To... (dropdown menu with other vocabularies)
  - Move To... (dropdown menu with other vocabularies)
  - Delete Selected (red)
  - Done (exit selection mode)

**Add Term Input:**
- TextField with placeholder "Add term"
- Plus button (`plus.circle.fill`)
- Disabled when input is empty or term count reaches 100

**Term List:**
- Each term displayed as a row
- In normal mode: delete button (`xmark.circle.fill`) on hover
- In selection mode: checkbox toggles (circle / checkmark.circle.fill)

**Footer:**
- Term count: "X / 100 terms"

### Window Footer

**Default Vocabulary Picker:**
- Segmented control: "Last used" / "Specific"
- If "Specific" selected → additional picker to choose a vocabulary

### Empty State

When no vocabulary is selected: centered text "Select a vocabulary".

---

## 7. Floating Overlay

**Type:** Floating panel (NSPanel), always on top.
**Size:** 400px wide, 60–300px tall (dynamic).
**Appearance:** Translucent HUD-style (`VisualEffectBlur`), rounded corners (10px).
**Behavior:** Non-activating (doesn't steal focus), movable by dragging, visible on all Spaces.

**Shown during:** Deepgram streaming recording.

### Layout

```
┌──────────────────────────────────────┐
│  [A]  Medical Vocabulary     01:23   │  ← Header
│                                      │
│  The transcribed text appears here   │  ← Scrollable text area
│  in real time as you speak...        │
└──────────────────────────────────────┘
```

### Header Row

| Element | Description |
|---------|-------------|
| Mode indicator | **"A"** (blue) = uppercase/new-sentence mode; **"a"** (orange) = continue/append mode |
| Vocabulary name | Name of active vocabulary (blinks during reconnection) |
| Return symbol (↵) | Shown when a vocabulary switch is pending confirmation |
| Timer | Elapsed recording time in MM:SS format (monospaced) |

### Transcription Area

- `ScrollView` with automatic scroll-to-bottom
- Displays `finalText` + `interimText` (interim shown in real-time)
- Maximum height: 250px (scrollable beyond that)

### Animations

| Trigger | Animation |
|---------|-----------|
| Window appears | Fade-in (0.15s) |
| Window dismisses | Fade-out (0.2s) |
| Reconnecting | Vocabulary name blinks (0.4s cycle) |
| Recording active | Pulse effect on status in main popover |

---

## 8. Global Hotkeys

### Recording Control

| Shortcut | Action | Default |
|----------|--------|---------|
| Primary hotkey | Toggle recording on/off | `Cmd+Shift+Space` |
| Mode toggle | Switch between uppercase/continue mode | `Down Arrow` |

### Overlay Controls (during Deepgram streaming only)

| Key | Action |
|-----|--------|
| `Left Arrow` | Cycle to previous vocabulary |
| `Right Arrow` | Cycle to next vocabulary |
| `Return` | Confirm vocabulary switch |

### Hotkey Recorder Behavior

- Requires at least one modifier key (Cmd, Shift, Option, Control)
- `Escape` cancels recording
- Displays pressed keys in real-time while recording
- "Reset" restores default hotkey

---

## 9. Navigation Flow

```
                        App Launch
                            │
                    ┌───────┴───────┐
                    │               │
             Permissions       Permissions
              missing            granted
                    │               │
                    ▼               ▼
            ┌──────────────┐  ┌──────────────┐
            │  Permissions │  │    Main       │
            │   Screen     │  │   Popover     │
            └──────┬───────┘  └──────┬────────┘
                   │                 │
            Grant all          ┌─────┼──────────┬──────────┐
                   │           │     │          │          │
                   ▼           ▼     ▼          ▼          ▼
            ┌──────────┐  History Settings Vocabulary   Quit
            │  Main    │  popover  popover   Manager
            │  Popover │                    (window)
            └──────────┘
                   │
            Press Record
                   │
            ┌──────┴──────────────┐
            │                     │
        WhisperKit            Deepgram
         (offline)           (streaming)
            │                     │
       Record audio          ┌────┴─────┐
       → Transcribe          │ Floating │
       → Insert              │ Overlay  │
            │                │ (panel)  │
            ▼                └────┬─────┘
         Done                     │
                             Stop recording
                                  │
                             Insert text
                                  │
                                Done
```

---

## 10. Text Insertion Behavior

After transcription completes, text is inserted into the previously focused application:

1. **Accessibility API** — directly sets the value of the focused text element (preferred method)
2. **Fallback: Clipboard paste** — copies text to clipboard and simulates `Cmd+V`

The app saves and restores the original clipboard content when using the fallback method.

---

## 11. Persistent Settings (UserDefaults)

| Key | Type | Description |
|-----|------|-------------|
| `deepgramEngine` | String | Selected engine: "deepgram" or "whisperkit" |
| `deepgramMode` | String | Deepgram mode: "streaming" or "rest" |
| `selectedWhisperModel` | String | WhisperKit model name |
| `hotKeyKeyCode` | UInt16 | Primary hotkey key code |
| `hotKeyModifiers` | UInt | Primary hotkey modifier flags |
| `modeToggleKeyCode` | UInt16 | Mode toggle key code |
| `vocabularies` | JSON | Array of vocabulary objects |
| `activeVocabularyId` | UUID | Currently active vocabulary |
| `vocabularyStartupMode` | String | "last" or "specific" |
| `defaultVocabularyId` | UUID | Default vocabulary for "specific" mode |

**Keychain:** Deepgram API key is stored securely in the macOS Keychain.
