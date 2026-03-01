# Overlay Enhancements Design

Date: 2026-02-28

## Overview

Four enhancements to the voice input overlay window:
1. Per-segment lowercase toggle
2. Backspace hotkey (delete char from end)
3. Space hotkey (append space to last segment)
4. Auto-expanding window anchored at bottom

---

## 1. Lowercase Toggle — Per-Segment Application

**Current:** `isContinueMode` lowercases first char of entire assembled text once during final insertion (`MenuBarViewModel` lines 373-376, 429-432).

**New:** Apply lowercase at segment finalization time in `OverlayViewModel.appendFinalText()`. If `isContinueMode == true` and segment's first character is uppercase — lowercase it. Result is immediately visible in the overlay.

**Changes:**
- `OverlayViewModel.appendFinalText()` — add `isContinueMode` check, lowercase first char before appending to `finalSegments`
- `MenuBarViewModel` lines 373-376, 429-432 — remove old lowercase logic (no longer needed at insertion time)

---

## 2. Backspace Hotkey

**Registration:** `KeyInterceptor` intercept keyCode 51 (Backspace), no modifiers. Hotkey config should be extractable for future reassignment (no hardcoded keyCode inline).

**Handler `handleBackspace()`:**
1. If `interimText` is not empty → set `isInterimBlocked = true`, return (no deletion)
2. If `finalSegments` is empty → return
3. Remove last character from `finalSegments.last.text`
4. If segment becomes empty → remove it from array
5. Sync via `replaceAccumulatedText()`

**Behavior chain across segments:**
```
Start:        [Hello world] [Good morning]
Backspace x13: [Hello world] []  → segment removed
Backspace x14: [Hello worl]      → continues from previous
...
Backspace x25: []                → segment removed
Backspace x26: nothing           → empty overlay
```

---

## 3. Space Hotkey

**Registration:** `KeyInterceptor` intercept keyCode 49 (Space), no modifiers. Same extractable config as Backspace.

**Handler `handleSpace()`:**
1. If `interimText` is not empty → set `isInterimBlocked = true`, return
2. If `finalSegments` is empty → return
3. If `finalSegments.last.text` already ends with `" "` → return (no duplicate spaces)
4. Append `" "` to `finalSegments.last.text`
5. Sync via `replaceAccumulatedText()`

---

## 4. Auto-Expanding Window (Bottom-Anchored)

**Current:** Fixed 400x60 at top of screen, max height 300px.

**New positioning:**
- Bottom edge: fixed offset from bottom of screen
- Horizontal: centered
- Growth direction: upward (top edge moves up as content grows)
- Max height: 50% of screen visible frame height
- Beyond max: ScrollView with auto-scroll to latest text

**Changes in `FloatingOverlayWindow`:**

### `updatePosition()`
- X = screen.midX - width/2
- Y = screen.visibleFrame.minY + bottomOffset
- Called once on show (bottom edge stays fixed)

### `updateSize()`
- Compute `fittingSize.height` from content
- Clamp: `min(max(fittingSize.height, 60), screen.visibleFrame.height * 0.5)`
- Preserve bottom edge: `frame.origin.y` stays the same, only height and `origin.y` adjusted so bottom is anchored
- Formula: `newOriginY = fixedBottomY` (origin.y doesn't change), frame height changes

### `OverlayContentView`
- Wrap text area in `ScrollView(.vertical)`
- Auto-scroll to bottom (latest text) on content change
- `ScrollViewReader` + `scrollTo(id, anchor: .bottom)` on segment/interim updates

---

## Hotkey Configuration (Future-Ready)

Space and Backspace hotkeys should use a config struct rather than hardcoded values:

```swift
struct HotkeyConfig {
    let keyCode: UInt16
    let modifiers: CGEventFlags
}
```

Currently defined as constants, but ready to be moved to user settings in the future. No settings UI for reassignment now.

---

## Files to Modify

| File | Changes |
|------|---------|
| `OverlayViewModel` (in FloatingOverlayWindow.swift) | `appendFinalText()` lowercase logic |
| `MenuBarViewModel` | Remove old lowercase logic, add `handleBackspace()`, `handleSpace()`, register hotkeys |
| `FloatingOverlayWindow` | Window positioning (bottom-anchored), `updateSize()` growth upward, ScrollView wrapping |
