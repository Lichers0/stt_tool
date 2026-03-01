# Overlay Bugfixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix 3 overlay bugs: window positioning drift, resize lag, lowercase not applied on insertion.

**Architecture:** All fixes are isolated changes in 2 files. Bug 1+2 are in `FloatingOverlayWindow.swift` (positioning and resize timing). Bug 3 is in `MenuBarViewModel.swift` (text source for insertion).

**Tech Stack:** Swift, AppKit (NSPanel), SwiftUI hosting

**Design doc:** `docs/plans/2026-03-01-overlay-bugfixes-design.md`

---

### Task 1: Fix window positioning — store screenOriginY

**Files:**
- Modify: `STTTool/Views/FloatingOverlayWindow.swift:4-8` (add property)
- Modify: `STTTool/Views/FloatingOverlayWindow.swift:161-174` (`positionOnScreen`)
- Modify: `STTTool/Views/FloatingOverlayWindow.swift:217-223` (`updateSize`)

**Step 1: Add `screenOriginY` property to FloatingOverlayWindow**

In `FloatingOverlayWindow`, add a stored property after `overlayViewModel`:

```swift
private var screenOriginY: CGFloat = 0
```

**Step 2: Save screenOriginY in positionOnScreen**

In `positionOnScreen(of:)`, after computing `y`, save it:

```swift
private func positionOnScreen(of targetApp: NSRunningApplication?) {
    let screen = screenForApp(targetApp) ?? NSScreen.main ?? NSScreen.screens.first
    guard let screen else { return }
    let visibleFrame = screen.visibleFrame
    let maxWindowHeight = visibleFrame.height * 0.5
    let headerAndPadding: CGFloat = 50
    overlayViewModel.maxTextHeight = maxWindowHeight - headerAndPadding

    let width: CGFloat = 400
    let height: CGFloat = 60
    let x = visibleFrame.midX - width / 2
    let y = visibleFrame.origin.y + 40
    screenOriginY = y                    // <-- NEW: store absolute bottom edge
    setFrame(NSRect(x: x, y: y, width: width, height: height), display: false)
}
```

**Step 3: Use screenOriginY in updateSize**

Replace `updateSize()`:

```swift
private func updateSize() {
    let fittingSize = hostingView.fittingSize
    let width: CGFloat = 400
    let height = max(fittingSize.height, 60)
    setFrame(NSRect(x: frame.origin.x, y: screenOriginY, width: width, height: height), display: true)
}
```

Changed: `frame.origin.y` → `screenOriginY`. Window always anchored to stored screen position.

**Step 4: Build and verify**

Run: `xcodebuild -project STTTool.xcodeproj -scheme STTTool build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```
fix: anchor overlay window to screen bottom edge

Store absolute screenOriginY on show, use it in updateSize()
instead of frame.origin.y. Fixes window drift on reopen and
expansion on paste.
```

---

### Task 2: Fix resize lag — async layout recalculation

**Files:**
- Modify: `STTTool/Views/FloatingOverlayWindow.swift:217-223` (`updateSize`)

**Step 1: Wrap updateSize body in DispatchQueue.main.async**

```swift
private func updateSize() {
    DispatchQueue.main.async { [self] in
        let fittingSize = hostingView.fittingSize
        let width: CGFloat = 400
        let height = max(fittingSize.height, 60)
        setFrame(NSRect(x: frame.origin.x, y: screenOriginY, width: width, height: height), display: true)
    }
}
```

This gives SwiftUI one RunLoop cycle to recalculate layout before we read `fittingSize`.

**Step 2: Build and verify**

Run: `xcodebuild -project STTTool.xcodeproj -scheme STTTool build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```
fix: async overlay resize for accurate fittingSize

Wrap updateSize() in DispatchQueue.main.async so SwiftUI
recalculates layout before we read hostingView.fittingSize.
Fixes resize lag when text is added.
```

---

### Task 3: Fix lowercase — use overlay text for insertion

**Files:**
- Modify: `STTTool/ViewModels/MenuBarViewModel.swift:353-391` (`stopDeepgramStreaming`)

**Step 1: Change text source in stopDeepgramStreaming**

Replace lines 370-371:

```swift
// Before:
var text = await deepgram.stopStreaming()
text = await services.textProcessingPipeline.process(text)

// After:
_ = await deepgram.stopStreaming()
var text = overlay.overlayFinalText
text = await services.textProcessingPipeline.process(text)
```

`deepgram.stopStreaming()` still called to close WebSocket properly, but its return value is discarded. Text comes from overlay — the source of truth that includes lowercase and all user edits.

**Step 2: Build and verify**

Run: `xcodebuild -project STTTool.xcodeproj -scheme STTTool build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```
fix: use overlay text for insertion instead of Deepgram

Overlay is the source of truth — it has lowercase applied,
paste edits, deletions. Deepgram accumulatedText doesn't
reflect these mutations.
```

---

### Task 4: Update TODO.md — mark bugs as fixed

**Files:**
- Modify: `TODO.md:9-10`

**Step 1: Mark both bugs as done in TODO.md**

Change lines 9-10 from `- [ ]` to `- [x]`.

**Step 2: Commit**

```
chore: mark overlay bugfixes as done in TODO
```

---

### Task 5: Manual verification

**Step 1: Build and run the app**

Run: `xcodebuild -project STTTool.xcodeproj -scheme STTTool build 2>&1 | tail -5`
Then launch the app.

**Step 2: Test positioning fix**
- Start dictation, speak a long text so window grows
- Stop dictation, wait for dismiss
- Start dictation again → window should appear at 40px from screen bottom (not shifted up)

**Step 3: Test paste expansion**
- Start dictation
- Copy a long text to clipboard
- Press Cmd+V → window should expand upward to fit pasted text

**Step 4: Test resize lag**
- Start dictation, speak quickly
- Observe window — should resize without visible clipping of new words

**Step 5: Test lowercase**
- Start dictation with lowercase mode (toggle to "a")
- Speak a sentence starting with capital letter
- Overlay should show lowercase
- Stop dictation → inserted text should also be lowercase (matching overlay)
