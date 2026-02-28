# Clipboard Paste Redesign — Controlled Paste Model

## Summary

Redesign the paste-during-dictation feature to only allow pasting when interim text is empty (all text finalized). Add visual feedback for blocked actions, color-coded text states, and Cmd+X for deleting the last word.

## Scope

- Deepgram streaming mode only
- Replaces the previous "paste anytime" approach with a controlled model

## Color Model

Four text states in the overlay, all pastel (subtle, not bright):

| State | Color | Approximate Value |
|-------|-------|-------------------|
| Interim (normal) | White | `.white` |
| Interim (blocked) | Pastel pink/red | `Color(red: 1.0, green: 0.7, blue: 0.7)` |
| Finalized (dictated) | Pastel green | `Color(red: 0.7, green: 1.0, blue: 0.7)` |
| Pasted | Pastel blue | `Color(red: 0.7, green: 0.85, blue: 1.0)` |

Exact values to be tuned during testing.

## Hotkey Actions

### Cmd+V (paste from clipboard)

- **Interim empty** → insert clipboard text as `.pasted` segment at end of `finalSegments`. Pastel blue color.
- **Interim not empty** → block. Interim text blinks pink 2 times (~0.3s each), then stays pink until finalized. When finalized → becomes green.

### Cmd+Z (undo last paste)

- **Works always**, regardless of interim state.
- Finds the last `.pasted` segment.
- Segment blinks 2 times in its color, then fades out (~0.3s).
- After fade completes → segment removed from array.
- No pasted segments → nothing happens.

### Cmd+X (delete last word)

- **Interim empty** → takes the last segment (any type), removes the last word. Word blinks 2 times, fades out. If segment becomes empty after removal → remove entire segment.
- **Interim not empty** → block (same pink highlight as paste).

## Animations

### Block animation (interim not empty)

1. `isInterimBlocked = true`
2. interimText color: white → pink → white → pink (2 blink cycles, ~0.3s each)
3. Stays pink
4. On finalize (`appendFinalText`): `isInterimBlocked = false`, text becomes green

### Removal animation (undo paste / delete word)

1. Mark segment/word as `removing`
2. Blink 2 times in segment's own color (blue for pasted, green for dictated)
3. Fade out (opacity → 0, ~0.3s)
4. On completion → remove from `finalSegments` array

## Architecture Simplification

The previous implementation had complex ordering logic (insert before trailing pastes, split rendering, overlay as source of truth). The new model eliminates all of this:

- **Paste only when interim empty** → paste always goes to end, no reordering needed
- **`appendFinalText`** → simple append (no insert-before-trailing-pastes logic)
- **`buildTextView`** → simple sequential render: `finalSegments` in order + `interimText` at end
- **Deepgram `accumulatedText`** synced from overlay via `replaceAccumulatedText` after mutations
- **`stopDeepgramStreaming`** → uses `deepgram.stopStreaming()` as source of final text (not overlay)

## Data Model

### OverlayViewModel changes

```swift
@Published var finalSegments: [TextSegment] = []
@Published var interimText = ""
@Published var isInterimBlocked = false       // pink highlight active
@Published var removingSegmentIndex: Int?     // segment being animated out
@Published var removingWordRange: Range<String.Index>?  // word being animated out

var finalText: String {
    finalSegments.map(\.text).joined()
}

func appendFinalText(_ text: String) {
    // Simple append as .dictated segment
    // Reset isInterimBlocked = false
}

func appendPastedText(_ text: String) {
    // Append as .pasted segment (only called when interim is empty)
}

func undoLastPaste() -> String? {
    // Find last .pasted segment, trigger removal animation
    // After animation: remove from array, return removed text
}

func deleteLastWord() -> String? {
    // Take last segment, remove last word, trigger removal animation
    // After animation: remove word (or entire segment if empty)
    // Return removed text
}
```

### DeepgramService changes

Add method:
```swift
func replaceAccumulatedText(_ text: String)
    // Replace accumulatedText entirely (for sync from overlay after mutations)
```

### MenuBarViewModel changes

- `handlePaste()`: check interim empty → call overlay + deepgram, or trigger block animation
- `handleUndoPaste()`: call overlay.undoLastPaste(), sync deepgram via replaceAccumulatedText
- `handleDeleteWord()`: check interim empty → call overlay.deleteLastWord(), sync deepgram, or trigger block animation
- Register Cmd+X (keyCode 7, .maskCommand) alongside Cmd+V and Cmd+Z

### FloatingOverlayWindow changes

- Remove `finalTranscriptText` computed property
- Remove complex `buildTextView` splitting logic
- Simple rendering: finalSegments in order (green/blue by type) + interimText (white or pink)

### Color constants

Add to `DS.Colors`:
```swift
static let interimBlocked = Color(red: 1.0, green: 0.7, blue: 0.7)
static let finalized = Color(red: 0.7, green: 1.0, blue: 0.7)
static let pasted = Color(red: 0.7, green: 0.85, blue: 1.0)
```

## Edge Cases

- **Empty clipboard on Cmd+V** → nothing happens (no block animation either)
- **Multiple Cmd+V when interim empty** → each creates separate pasted segment
- **Cmd+Z with no pasted segments** → nothing happens
- **Cmd+X on empty finalSegments** → nothing happens
- **Cmd+X on segment with one word** → removes entire segment
- **Rapid Cmd+X** → each press removes one word (queued if animation in progress)
- **Cmd+Z during interim** → works, removes last paste with animation
