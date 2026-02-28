# Clipboard Paste During Dictation — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Allow pasting clipboard text (Cmd+V) into the transcript during Deepgram streaming recording, with undo (Cmd+Z) and subtle visual distinction for pasted segments.

**Architecture:** Extend `OverlayViewModel` to use a segment-based model (`[TextSegment]`) instead of a plain `finalText` string. Add modifier-aware key interception to `KeyInterceptor`. Wire paste/undo handlers in `MenuBarViewModel` that update both overlay and Deepgram's `accumulatedText`.

**Tech Stack:** Swift 6.0, SwiftUI, CoreGraphics (CGEventTap), AppKit (NSPasteboard)

---

### Task 1: Add TextSegment model and refactor OverlayViewModel

**Files:**
- Modify: `STTTool/Views/FloatingOverlayWindow.swift:168-215` (OverlayViewModel)

**Step 1: Add TextSegment types above OverlayViewModel**

Add before `class OverlayViewModel` (line 168):

```swift
enum TextSegmentType {
    case dictated
    case pasted
}

struct TextSegment {
    let text: String
    let type: TextSegmentType
}
```

**Step 2: Replace `finalText` with `finalSegments` in OverlayViewModel**

Replace property (line 169):
```swift
// OLD:
@Published var finalText = ""

// NEW:
@Published var finalSegments: [TextSegment] = []
```

Add computed `finalText` for backward compatibility:
```swift
var finalText: String {
    finalSegments.map(\.text).joined()
}
```

**Step 3: Update `appendFinalText` method**

Replace method at line 187-192:
```swift
func appendFinalText(_ text: String) {
    let needsSpace = !finalSegments.isEmpty && !(finalSegments.last?.text.hasSuffix(" ") ?? true)
    let paddedText = needsSpace ? " " + text : text
    finalSegments.append(TextSegment(text: paddedText, type: .dictated))
}
```

**Step 4: Add `appendPastedText` and `undoLastPaste` methods**

```swift
func appendPastedText(_ text: String) {
    guard !text.isEmpty else { return }
    let needsSpace = !finalSegments.isEmpty && !(finalSegments.last?.text.hasSuffix(" ") ?? true)
    let padded = (needsSpace ? " " : "") + text + (text.hasSuffix(" ") ? "" : " ")
    finalSegments.append(TextSegment(text: padded, type: .pasted))
}

/// Removes the last pasted segment. Returns the removed text or nil.
@discardableResult
func undoLastPaste() -> String? {
    guard let lastPasteIndex = finalSegments.lastIndex(where: { $0.type == .pasted }) else {
        return nil
    }
    let removed = finalSegments.remove(at: lastPasteIndex)
    return removed.text
}
```

**Step 5: Update `reset()` method**

Replace `finalText = ""` with `finalSegments = []` inside `reset()` (line 194-204).

**Step 6: Update `displayText` computed property**

Replace at line 206-214:
```swift
var displayText: String {
    let final = finalText
    if !interimText.isEmpty {
        if final.isEmpty {
            return interimText
        }
        return final + " " + interimText
    }
    return final
}
```

(Uses the new computed `finalText` — same logic, just delegates to segments.)

**Step 7: Build and verify no compiler errors**

Run: `xcodebuild build -project STTTool.xcodeproj -scheme STTTool -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 8: Commit**

```
feat: replace finalText with segment-based model in OverlayViewModel
```

---

### Task 2: Update OverlayContentView to render segments with color

**Files:**
- Modify: `STTTool/Views/FloatingOverlayWindow.swift:219-326` (OverlayContentView)

**Step 1: Add a helper method to build segmented Text view**

Add a method inside `OverlayContentView`:

```swift
@ViewBuilder
private func segmentedText() -> some View {
    if viewModel.finalSegments.isEmpty && viewModel.interimText.isEmpty {
        Text("Listening...")
            .font(DS.Typography.caption)
            .italic()
            .foregroundStyle(.secondary.opacity(0.5))
    } else {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                buildTextView()
                    .font(DS.Typography.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id("bottom")
            }
            .onChange(of: viewModel.displayText) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
        .frame(maxHeight: 250)
    }
}

private func buildTextView() -> Text {
    var result = Text("")

    for segment in viewModel.finalSegments {
        let color: Color = segment.type == .pasted
            ? .white.opacity(0.7)
            : .white
        result = result + Text(segment.text).foregroundColor(color)
    }

    if !viewModel.interimText.isEmpty {
        let spacer = viewModel.finalSegments.isEmpty ? "" : " "
        result = result + Text(spacer + viewModel.interimText).foregroundColor(.white)
    }

    return result
}
```

**Step 2: Replace the transcription text section in `body`**

Replace the block at lines 293-311 (from `// Transcription text` to the end of the ScrollView .frame modifier) with:

```swift
// Transcription text
segmentedText()
```

**Step 3: Build and verify**

Run: `xcodebuild build -project STTTool.xcodeproj -scheme STTTool -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```
feat: render pasted segments with subtle color distinction in overlay
```

---

### Task 3: Add modifier-aware interception to KeyInterceptor

**Files:**
- Modify: `STTTool/Services/KeyInterceptor.swift`

**Step 1: Define a composite key for handler lookup**

Replace `handlers` dictionary type (line 12):

```swift
// OLD:
private var handlers: [UInt16: () -> Void] = [:]

// NEW:
private struct KeyCombo: Hashable {
    let keyCode: UInt16
    let modifiers: CGEventFlags

    // Only compare relevant modifier bits
    static let relevantFlags: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]

    func matches(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        self.keyCode == keyCode && self.modifiers == flags.intersection(KeyCombo.relevantFlags)
    }
}

private var handlers: [KeyCombo: () -> Void] = [:]
```

**Step 2: Update `intercept` method to accept optional modifiers**

Replace at line 48-53:

```swift
/// Register a handler for a specific keyCode with optional modifier keys.
/// The key event will be consumed when matched.
func intercept(keyCode: UInt16, modifiers: CGEventFlags = [], handler: @escaping () -> Void) {
    let combo = KeyCombo(keyCode: keyCode, modifiers: modifiers.intersection(KeyCombo.relevantFlags))
    lock.lock()
    handlers[combo] = handler
    lock.unlock()
    ensureTapEnabled()
}
```

**Step 3: Update `stopIntercepting` to accept optional modifiers**

Replace at line 56-60:

```swift
func stopIntercepting(keyCode: UInt16, modifiers: CGEventFlags = []) {
    let combo = KeyCombo(keyCode: keyCode, modifiers: modifiers.intersection(KeyCombo.relevantFlags))
    lock.lock()
    handlers.removeValue(forKey: combo)
    lock.unlock()
}
```

**Step 4: Update `handleKeyEvent` to check modifiers**

Replace at line 72-82:

```swift
fileprivate func handleKeyEvent(_ keyCode: UInt16, flags: CGEventFlags) -> Bool {
    lock.lock()
    let matchedHandler = handlers.first { $0.key.matches(keyCode: keyCode, flags: flags) }?.value
    lock.unlock()

    if let handler = matchedHandler {
        DispatchQueue.main.async { handler() }
        return true // consumed
    }
    return false // pass through
}
```

**Step 5: Update the C callback to pass flags**

In `keyInterceptorCallback` (line 114-118), change:

```swift
// OLD:
let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
let interceptor = Unmanaged<KeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
if interceptor.handleKeyEvent(keyCode) {

// NEW:
let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
let flags = event.flags
let interceptor = Unmanaged<KeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
if interceptor.handleKeyEvent(keyCode, flags: flags) {
```

**Step 6: Build and verify**

Run: `xcodebuild build -project STTTool.xcodeproj -scheme STTTool -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 7: Commit**

```
feat: add modifier-aware key interception to KeyInterceptor
```

---

### Task 4: Add public method to DeepgramService for inserting/removing text

**Files:**
- Modify: `STTTool/Services/DeepgramService.swift`

**Step 1: Add `insertAccumulatedText` method**

Add after `cancelStreaming()` method (~line 212):

```swift
/// Insert external text (e.g. clipboard paste) into the accumulated transcript.
func insertAccumulatedText(_ text: String) {
    lock.lock()
    if !accumulatedText.isEmpty && !accumulatedText.hasSuffix(" ") {
        accumulatedText += " "
    }
    accumulatedText += text
    lock.unlock()
}

/// Remove a previously inserted text from the end of accumulated transcript.
func removeAccumulatedText(_ text: String) {
    lock.lock()
    if accumulatedText.hasSuffix(text) {
        accumulatedText.removeLast(text.count)
    }
    lock.unlock()
}
```

**Step 2: Build and verify**

Run: `xcodebuild build -project STTTool.xcodeproj -scheme STTTool -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```
feat: add insert/remove text methods to DeepgramService
```

---

### Task 5: Wire paste (Cmd+V) and undo (Cmd+Z) in MenuBarViewModel

**Files:**
- Modify: `STTTool/ViewModels/MenuBarViewModel.swift`

**Step 1: Add `appendPastedText` and `undoLastPaste` to FloatingOverlayWindow**

Add public methods to `FloatingOverlayWindow` (after `setReconnecting`):

File: `STTTool/Views/FloatingOverlayWindow.swift`, after line 77:

```swift
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
```

**Step 2: Add register/unregister methods for paste and undo in MenuBarViewModel**

Add after `unregisterOverlayHotkeys()` method (~line 530):

```swift
private func registerPasteAndUndo() {
    // Cmd+V — paste from clipboard
    KeyInterceptor.shared.intercept(keyCode: 9, modifiers: .maskCommand) { [weak self] in
        Task { @MainActor in
            self?.handlePaste()
        }
    }
    // Cmd+Z — undo last paste
    KeyInterceptor.shared.intercept(keyCode: 6, modifiers: .maskCommand) { [weak self] in
        Task { @MainActor in
            self?.handleUndoPaste()
        }
    }
}

private func unregisterPasteAndUndo() {
    KeyInterceptor.shared.stopIntercepting(keyCode: 9, modifiers: .maskCommand)
    KeyInterceptor.shared.stopIntercepting(keyCode: 6, modifiers: .maskCommand)
}

private func handlePaste() {
    guard appState == .streamingRecording else { return }
    guard let text = NSPasteboard.general.string(forType: .string),
          !text.isEmpty else { return }

    overlay.appendPastedText(text)

    nonisolated(unsafe) let deepgram = services.deepgramService
    let padded = text + (text.hasSuffix(" ") ? "" : " ")
    deepgram.insertAccumulatedText(padded)

    print("[Paste] Inserted clipboard text: \"\(text.prefix(40))...\"")
}

private func handleUndoPaste() {
    guard appState == .streamingRecording else { return }

    guard let removed = overlay.undoLastPaste() else { return }

    nonisolated(unsafe) let deepgram = services.deepgramService
    deepgram.removeAccumulatedText(removed)

    print("[Paste] Undo last paste: \"\(removed.prefix(40))...\"")
}
```

**Step 3: Register in `startDeepgramStreaming`**

In `startDeepgramStreaming` method, after `services.hotKeyService.registerCancel()` (line 299), add:

```swift
registerPasteAndUndo()
```

**Step 4: Unregister in all stop/cancel paths**

Add `unregisterPasteAndUndo()` in three places:

1. `stopRecordingAndTranscribe()` — after `unregisterOverlayHotkeys()` (line 333)
2. `cancelRecording()` — after `unregisterOverlayHotkeys()` (line 128)
3. `deepgram.onError` callback — after `self?.services.hotKeyService.unregisterCancel()` (line 265)

**Step 5: Build and verify**

Run: `xcodebuild build -project STTTool.xcodeproj -scheme STTTool -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 6: Commit**

```
feat: wire Cmd+V paste and Cmd+Z undo during Deepgram streaming
```

---

### Task 6: Manual testing

**Step 1: Run the app**

Run: `open STTTool.xcodeproj` and run (Cmd+R)

**Step 2: Test paste during dictation**

1. Copy some text to clipboard (e.g. "myFunction()")
2. Start Deepgram streaming recording (Cmd+Shift+Space)
3. Dictate a few words — verify they appear in overlay
4. Press Cmd+V — verify pasted text appears with slightly dimmer color
5. Continue dictating — verify next words don't merge with pasted text (space is present)
6. Stop recording — verify final inserted text contains both dictated and pasted parts

**Step 3: Test undo**

1. During recording, paste some text with Cmd+V
2. Press Cmd+Z — verify the pasted segment disappears from overlay
3. Continue dictating — verify everything works normally

**Step 4: Test edge cases**

- Cmd+V with empty clipboard — nothing happens
- Multiple Cmd+V — each creates a separate segment
- Cmd+Z without any paste — nothing happens
- Cmd+V then Cmd+Z then Cmd+V again — works correctly
- Paste at the very start (before any dictation)

**Step 5: Commit version bump (ask user about version)**

```
chore: bump version to X.Y.Z
```
