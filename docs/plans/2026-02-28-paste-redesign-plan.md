# Paste Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Redesign paste-during-dictation to a controlled model: paste/delete only when interim text is empty, with color-coded text states and block/removal animations.

**Architecture:** Simplify OverlayViewModel (remove complex ordering logic), add color states and animation flags, add `replaceAccumulatedText` to DeepgramService for sync, rewire MenuBarViewModel handlers with interim-empty checks and Cmd+X support.

**Tech Stack:** Swift 6.0, SwiftUI, CoreGraphics (CGEventTap), AppKit (NSPasteboard)

---

### Task 1: Add overlay color constants to DesignSystem

**Files:**
- Modify: `STTTool/Views/DesignSystem.swift:9-37`

**Step 1: Add overlay text colors after the existing `// Permission states` block (line 36)**

```swift
// Overlay text states (pastel tones)
static let overlayInterim = Color.white
static let overlayInterimBlocked = Color(red: 1.0, green: 0.7, blue: 0.7)
static let overlayFinalized = Color(red: 0.7, green: 1.0, blue: 0.7)
static let overlayPasted = Color(red: 0.7, green: 0.85, blue: 1.0)
```

**Step 2: Build and verify**

Run: `xcodebuild build -project STTTool.xcodeproj -scheme STTTool -destination 'platform=macOS' 2>&1 | tail -5`

**Step 3: Commit**

```
feat: add pastel overlay text colors to DesignSystem
```

---

### Task 2: Simplify OverlayViewModel — remove ordering complexity, add new state

**Files:**
- Modify: `STTTool/Views/FloatingOverlayWindow.swift:200-277` (OverlayViewModel)

**Step 1: Replace `appendFinalText` — simple append, reset blocked state**

Replace lines 224-234 with:

```swift
func appendFinalText(_ text: String) {
    let needsSpace = !finalSegments.isEmpty && !(finalSegments.last?.text.hasSuffix(" ") ?? true)
    let paddedText = needsSpace ? " " + text : text
    finalSegments.append(TextSegment(text: paddedText, type: .dictated))
    isInterimBlocked = false
}
```

**Step 2: Replace `appendPastedText` — add leading space back**

Replace lines 236-243 with:

```swift
func appendPastedText(_ text: String) {
    guard !text.isEmpty else { return }
    let needsSpace = !finalSegments.isEmpty && !(finalSegments.last?.text.hasSuffix(" ") ?? true)
    let padded = (needsSpace ? " " : "") + text + (text.hasSuffix(" ") ? "" : " ")
    finalSegments.append(TextSegment(text: padded, type: .pasted))
}
```

**Step 3: Add `isInterimBlocked` and `removingSegmentId` published properties**

Add after `@Published var isConnecting = true` (line 214):

```swift
@Published var isInterimBlocked = false
@Published var removingSegmentId: UUID?
```

**Step 4: Update TextSegment to have an `id`**

Replace the `TextSegment` struct (lines 195-198) with:

```swift
struct TextSegment: Identifiable {
    let id = UUID()
    let text: String
    let type: TextSegmentType
}
```

**Step 5: Make `text` mutable for word deletion**

Change `let text: String` to `var text: String` in TextSegment.

**Step 6: Add `deleteLastWord` method**

Add after `undoLastPaste()`:

```swift
/// Removes the last word from the last segment. Returns the removed word or nil.
func deleteLastWord() -> String? {
    guard !finalSegments.isEmpty else { return nil }
    var lastSegment = finalSegments[finalSegments.count - 1]
    let trimmed = lastSegment.text.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else {
        finalSegments.removeLast()
        return deleteLastWord()
    }

    let words = trimmed.components(separatedBy: " ")
    guard let lastWord = words.last, !lastWord.isEmpty else { return nil }

    // Remove last word from segment text
    if words.count <= 1 {
        // Entire segment is one word — remove the segment
        let removed = finalSegments.removeLast()
        return removed.text.trimmingCharacters(in: .whitespaces)
    } else {
        // Remove last word, keep trailing space
        let newText = words.dropLast().joined(separator: " ") + " "
        finalSegments[finalSegments.count - 1] = TextSegment(text: newText, type: lastSegment.type)
        return lastWord
    }
}
```

Note: `TextSegment` gets a new `id` on replacement — this is fine because SwiftUI uses `removingSegmentId` for animations, not array identity.

**Step 7: Update `reset()` to clear new properties**

Add to reset():

```swift
isInterimBlocked = false
removingSegmentId = nil
```

**Step 8: Build and verify**

Run: `xcodebuild build -project STTTool.xcodeproj -scheme STTTool -destination 'platform=macOS' 2>&1 | tail -5`

**Step 9: Commit**

```
refactor: simplify OverlayViewModel, add block state and word deletion
```

---

### Task 3: Rewrite buildTextView — simple rendering with color states

**Files:**
- Modify: `STTTool/Views/FloatingOverlayWindow.swift:365-424` (OverlayContentView)

**Step 1: Add blink animation state**

Add after `@State private var dotPulse = false` (line 285):

```swift
@State private var interimBlinkPhase = false
```

**Step 2: Replace `buildTextView` entirely**

Replace the current `buildTextView` method (lines 388-424) with:

```swift
private func buildTextView() -> Text {
    var result = Text("")

    for segment in viewModel.finalSegments {
        let color: Color = switch segment.type {
        case .dictated: DS.Colors.overlayFinalized
        case .pasted: DS.Colors.overlayPasted
        }
        let isRemoving = viewModel.removingSegmentId == segment.id
        let opacity: Double = isRemoving ? 0.0 : 1.0
        result = result + Text(segment.text)
            .foregroundColor(color.opacity(opacity))
    }

    if !viewModel.interimText.isEmpty {
        let spacer = viewModel.finalSegments.isEmpty ? "" : " "
        let interimColor: Color = viewModel.isInterimBlocked
            ? DS.Colors.overlayInterimBlocked
            : DS.Colors.overlayInterim
        result = result + Text(spacer + viewModel.interimText)
            .foregroundColor(interimColor)
    }

    return result
}
```

**Step 3: Add onChange handler for `isInterimBlocked` to trigger blink animation**

Inside the `segmentedText()` method, after the `.frame(maxHeight: 250)` modifier, add:

```swift
.onChange(of: viewModel.isInterimBlocked) { _, blocked in
    if blocked {
        // Blink 2 times then stay
        interimBlinkPhase = true
        withAnimation(.easeInOut(duration: 0.15).repeatCount(4, autoreverses: true)) {
            interimBlinkPhase = false
        }
    }
}
```

Note: The blink animation is handled via the color change triggered by `isInterimBlocked` — when it becomes true, the SwiftUI Text color reactively switches to pink. The blink effect is the rapid on/off of `isInterimBlocked` controlled from the ViewModel (2 toggles with delay). For simplicity, just set `isInterimBlocked = true` and let the color change be instant — the 2 blinks can be done by toggling the property with short delays in the handler.

**Step 4: Build and verify**

Run: `xcodebuild build -project STTTool.xcodeproj -scheme STTTool -destination 'platform=macOS' 2>&1 | tail -5`

**Step 5: Commit**

```
feat: rewrite overlay rendering with color-coded text states
```

---

### Task 4: Add `replaceAccumulatedText` to DeepgramService

**Files:**
- Modify: `STTTool/Services/DeepgramService.swift`
- Modify: `STTTool/Services/ServiceContainer.swift:116-130` (protocol)

**Step 1: Add `replaceAccumulatedText` method to DeepgramService**

Add after `removeAccumulatedText` method (~line 233):

```swift
/// Replace accumulated text entirely (for sync from overlay after mutations).
func replaceAccumulatedText(_ text: String) {
    lock.lock()
    accumulatedText = text
    lock.unlock()
}
```

**Step 2: Add to `DeepgramServiceProtocol`**

In `ServiceContainer.swift`, add after `func removeAccumulatedText(_ text: String)` (line 129):

```swift
func replaceAccumulatedText(_ text: String)
```

**Step 3: Build and verify**

Run: `xcodebuild build -project STTTool.xcodeproj -scheme STTTool -destination 'platform=macOS' 2>&1 | tail -5`

**Step 4: Commit**

```
feat: add replaceAccumulatedText to DeepgramService
```

---

### Task 5: Rewire MenuBarViewModel — controlled paste, undo, delete word

**Files:**
- Modify: `STTTool/ViewModels/MenuBarViewModel.swift`
- Modify: `STTTool/Views/FloatingOverlayWindow.swift` (pass-through methods)

**Step 1: Update FloatingOverlayWindow pass-through methods**

Replace the existing `appendPastedText` and `undoLastPaste` methods and add new ones. Remove `finalTranscriptText`. After `setReconnecting` (line 77):

```swift
var isInterimEmpty: Bool {
    overlayViewModel.interimText.isEmpty
}

func triggerInterimBlocked() {
    overlayViewModel.isInterimBlocked = true
    // Blink: toggle off/on twice, then stay on
    Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(150))
        overlayViewModel.isInterimBlocked = false
        try? await Task.sleep(for: .milliseconds(150))
        overlayViewModel.isInterimBlocked = true
        try? await Task.sleep(for: .milliseconds(150))
        overlayViewModel.isInterimBlocked = false
        try? await Task.sleep(for: .milliseconds(150))
        overlayViewModel.isInterimBlocked = true
    }
}

func appendPastedText(_ text: String) {
    overlayViewModel.appendPastedText(text)
    updateSize()
}

@discardableResult
func undoLastPaste() -> String? {
    let removed = overlayViewModel.undoLastPaste()
    updateSize()
    return removed
}

func deleteLastWord() -> String? {
    let removed = overlayViewModel.deleteLastWord()
    updateSize()
    return removed
}

var overlayFinalText: String {
    overlayViewModel.finalText
}
```

Remove the `finalTranscriptText` computed property (lines 91-100).

**Step 2: Rename `registerPasteAndUndo` → `registerEditHotkeys` and add Cmd+X**

Replace `registerPasteAndUndo()` and `unregisterPasteAndUndo()` in MenuBarViewModel:

```swift
private func registerEditHotkeys() {
    // Cmd+V — paste from clipboard
    KeyInterceptor.shared.intercept(keyCode: 9, modifiers: .maskCommand) { [weak self] in
        Task { @MainActor in self?.handlePaste() }
    }
    // Cmd+Z — undo last paste
    KeyInterceptor.shared.intercept(keyCode: 6, modifiers: .maskCommand) { [weak self] in
        Task { @MainActor in self?.handleUndoPaste() }
    }
    // Cmd+X — delete last word
    KeyInterceptor.shared.intercept(keyCode: 7, modifiers: .maskCommand) { [weak self] in
        Task { @MainActor in self?.handleDeleteWord() }
    }
}

private func unregisterEditHotkeys() {
    KeyInterceptor.shared.stopIntercepting(keyCode: 9, modifiers: .maskCommand)
    KeyInterceptor.shared.stopIntercepting(keyCode: 6, modifiers: .maskCommand)
    KeyInterceptor.shared.stopIntercepting(keyCode: 7, modifiers: .maskCommand)
}
```

**Step 3: Replace handler methods**

```swift
private func syncDeepgramFromOverlay() {
    nonisolated(unsafe) let deepgram = services.deepgramService
    deepgram.replaceAccumulatedText(overlay.overlayFinalText)
}

private func handlePaste() {
    guard appState == .streamingRecording else { return }
    guard let text = NSPasteboard.general.string(forType: .string),
          !text.isEmpty else { return }

    guard overlay.isInterimEmpty else {
        overlay.triggerInterimBlocked()
        print("[Paste] Blocked — interim text present")
        return
    }

    overlay.appendPastedText(text)
    syncDeepgramFromOverlay()
    print("[Paste] Inserted clipboard text: \"\(text.prefix(40))...\"")
}

private func handleUndoPaste() {
    guard appState == .streamingRecording else { return }
    guard overlay.undoLastPaste() != nil else { return }
    syncDeepgramFromOverlay()
    print("[Paste] Undo last paste")
}

private func handleDeleteWord() {
    guard appState == .streamingRecording else { return }

    guard overlay.isInterimEmpty else {
        overlay.triggerInterimBlocked()
        print("[DeleteWord] Blocked — interim text present")
        return
    }

    guard overlay.deleteLastWord() != nil else { return }
    syncDeepgramFromOverlay()
    print("[DeleteWord] Deleted last word")
}
```

**Step 4: Update all call sites**

Replace all occurrences of `registerPasteAndUndo()` with `registerEditHotkeys()` and `unregisterPasteAndUndo()` with `unregisterEditHotkeys()` in:
- `startDeepgramStreaming` (line 302)
- `stopRecordingAndTranscribe` (line 337)
- `cancelRecording` (line 129)
- `deepgram.onError` callback (line 267)

**Step 5: Revert `stopDeepgramStreaming` to use deepgram as text source**

Replace lines 370-376:

```swift
// OLD:
_ = await deepgram.stopStreaming()
var text = overlay.finalTranscriptText

// NEW:
var text = await deepgram.stopStreaming()
```

Keep the rest unchanged.

**Step 6: Build and verify**

Run: `xcodebuild build -project STTTool.xcodeproj -scheme STTTool -destination 'platform=macOS' 2>&1 | tail -5`

**Step 7: Commit**

```
feat: rewire paste/undo/delete-word with controlled model
```

---

### Task 6: Manual testing

**Step 1: Build and run the app**

**Step 2: Test color states**

1. Start Deepgram streaming recording
2. Speak — interim text should be white
3. Wait for finalization — text should become pastel green
4. Paste (Cmd+V when interim empty) — pasted text should be pastel blue

**Step 3: Test paste blocking**

1. Start speaking (interim text visible, white)
2. Press Cmd+V — interim text blinks pink, stays pink, paste does NOT happen
3. Stop speaking — text finalizes, becomes green, pink goes away
4. Now press Cmd+V — paste works

**Step 4: Test Cmd+Z (undo paste)**

1. Paste some text
2. Start speaking (interim text visible)
3. Press Cmd+Z — pasted segment disappears even though interim exists
4. Verify deepgram accumulatedText is synced

**Step 5: Test Cmd+X (delete last word)**

1. Dictate "hello world" → finalized (green)
2. Press Cmd+X → "world" removed, "hello " remains
3. Press Cmd+X → "hello" removed, empty
4. Test during interim → should block with pink highlight

**Step 6: Test edge cases**

- Cmd+V with empty clipboard → nothing happens
- Cmd+X on empty segments → nothing happens
- Cmd+Z with no pastes → nothing happens
- Multiple Cmd+X rapidly → each removes one word

**Step 7: Version bump (ask user)**

```
chore: bump version to X.Y.Z
```
