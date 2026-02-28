# Clipboard Paste During Dictation

## Summary

Allow pasting text from clipboard (Cmd+V) into the accumulated transcript during Deepgram streaming recording. Support undo (Cmd+Z) for the last paste. Pasted segments are visually distinguished in the overlay with a subtly different color.

## Scope

- Deepgram streaming mode only
- WhisperKit mode is not affected

## Data Model

```swift
enum SegmentType { case dictated, pasted }

struct TextSegment {
    let text: String
    let type: SegmentType
}
```

## OverlayViewModel Changes

Replace `finalText: String` with `finalSegments: [TextSegment]`.

Keep `interimText: String` as-is (always dictated, temporary).

Methods:
- `appendFinalText(_ text:)` — creates `.dictated` segment (existing behavior, renamed internally)
- `appendPastedText(_ text:)` — creates `.pasted` segment, ensures trailing space
- `undoLastPaste()` — removes the last `.pasted` segment from `finalSegments`
- Computed `finalText: String` — joins all segments for backward compatibility

### Display

SwiftUI renders segments via `Text` concatenation:
- `.dictated` segments: `.white` (current color)
- `.pasted` segments: `.white.opacity(0.7)` (subtle distinction)
- `interimText` appended at the end as before

## KeyInterceptorService Changes

Add modifier support to key interception:
- `intercept(keyCode:modifiers:handler:)` — optional `CGEventFlags` parameter
- Callback checks `event.flags.contains(requiredModifier)` when modifiers are specified
- Existing handlers (Esc, arrows, Enter) remain unchanged (no modifiers)

New intercepted keys during Deepgram streaming:
- **Cmd+V** (keyCode 9 + `.maskCommand`): paste from clipboard
- **Cmd+Z** (keyCode 6 + `.maskCommand`): undo last paste

Both events are consumed (return `nil`) — they do not pass through to the target app.

## MenuBarViewModel Integration

### Registration

In `startDeepgramStreaming()`, alongside existing `registerCancel()`:
- `registerPaste()` — registers Cmd+V handler
- `registerUndo()` — registers Cmd+Z handler

In `stopRecordingAndTranscribe()` and `cancelRecording()`:
- Unregister both handlers

### Cmd+V Handler

1. Read `NSPasteboard.general.string(forType: .string)`
2. If empty or nil — ignore
3. Call `overlay.appendPastedText(text)`
4. Update `deepgram.accumulatedText` by appending the pasted text (with trailing space)

### Cmd+Z Handler

1. Call `overlay.undoLastPaste()` — returns the removed text (or nil if no paste segments)
2. If text was removed — update `deepgram.accumulatedText` by removing it

MenuBarViewModel acts as coordinator, updating both overlay (for display) and deepgram (for final result) in parallel.

## Trailing Space Guarantee

`appendPastedText()` ensures the segment text ends with a space:
```swift
func appendPastedText(_ text: String) {
    let padded = text.hasSuffix(" ") ? text : text + " "
    finalSegments.append(TextSegment(text: padded, type: .pasted))
}
```

This prevents the next dictated word from merging with the pasted text.

## Edge Cases

- **Empty clipboard**: Cmd+V does nothing
- **Multiple pastes**: each creates a separate `.pasted` segment; Cmd+Z removes only the last one
- **No paste segments when Cmd+Z**: nothing happens, event is still consumed
- **Paste at the very beginning**: works fine — first segment is `.pasted`
- **WhisperKit mode**: Cmd+V/Z are not registered, no effect

## Final Insertion Flow

No changes to `insertText()`. The `accumulatedText` already contains everything (dictated + pasted). The existing Cmd+V insertion into the target app works as before.
