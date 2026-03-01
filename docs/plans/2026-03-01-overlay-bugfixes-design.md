# Overlay Bugfixes Design

**Date:** 2026-03-01
**Scope:** 3 bugs in FloatingOverlayWindow

## Bug 1: Window positioning — drifts on reopen, doesn't expand on paste

### Problem
- `updateSize()` uses `frame.origin.y` as anchor — unreliable after resize cycles
- On reopen after large text session, window appears at wrong position
- On Cmd+V paste, window doesn't expand upward

### Solution
- Store `screenOriginY` (absolute bottom edge = `visibleFrame.origin.y + 40`) in `positionOnScreen`
- `updateSize()` always computes `y = screenOriginY` instead of `frame.origin.y`
- Keep `isMovableByWindowBackground = true` — user can still drag the window
- Each `showForRecording` resets position to 40px from screen bottom

### Files
- `FloatingOverlayWindow.swift`: add `screenOriginY` property, update `positionOnScreen`, update `updateSize()`

---

## Bug 2: Window resize lag — fittingSize returns stale value

### Problem
- `updateSize()` is called synchronously right after `@Published` property updates
- SwiftUI hasn't recalculated layout yet → `hostingView.fittingSize` returns old size
- Window resize lags behind text changes by one update cycle

### Solution
- Wrap size recalculation in `DispatchQueue.main.async` to give SwiftUI one RunLoop cycle
- After that cycle, `fittingSize` reflects the actual content size
- Applies to all `updateSize()` call sites: interim text, final segment, paste, delete, space

### Files
- `FloatingOverlayWindow.swift`: change `updateSize()` to use `DispatchQueue.main.async`

---

## Bug 3: Lowercase toggle not applied on final text insertion

### Problem
- `stopDeepgramStreaming()` uses `deepgram.stopStreaming()` text (original, no lowercase)
- Overlay stores lowercased text in `finalSegments`, but it's ignored at insertion time
- User sees "hello" in overlay, but "Hello" gets inserted

### Solution
- Use `overlay.overlayFinalText` as source of truth for insertion
- Still call `deepgram.stopStreaming()` to properly close WebSocket, but discard its text
- `textProcessingPipeline.process()` still applies to overlay text (currently passthrough)

### Files
- `MenuBarViewModel.swift`: change `stopDeepgramStreaming()` to use `overlay.overlayFinalText`
