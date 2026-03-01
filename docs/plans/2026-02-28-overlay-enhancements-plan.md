# Overlay Enhancements Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add per-segment lowercase, Backspace/Space hotkeys, and auto-expanding bottom-anchored overlay window.

**Architecture:** Four independent changes to OverlayViewModel, MenuBarViewModel, and FloatingOverlayWindow. Hotkey configs use extractable struct for future reassignment. Window growth uses Cocoa frame manipulation to anchor bottom edge.

**Tech Stack:** Swift 6.0, SwiftUI, AppKit (NSPanel), CGEventTap

---

### Task 1: Per-Segment Lowercase Toggle

**Files:**
- Modify: `STTTool/Views/FloatingOverlayWindow.swift:244-248` (OverlayViewModel.appendFinalText)
- Modify: `STTTool/ViewModels/MenuBarViewModel.swift:373-376,429-432` (remove old lowercase logic)

**Step 1: Add lowercase logic to appendFinalText**

In `FloatingOverlayWindow.swift`, modify `OverlayViewModel.appendFinalText()` (line 244):

```swift
func appendFinalText(_ text: String) {
    let needsSpace = !finalSegments.isEmpty && !(finalSegments.last?.text.hasSuffix(" ") ?? true)
    var paddedText = needsSpace ? " " + text : text

    // Apply per-segment lowercase when continue mode is active
    if isContinueMode {
        let textPart = needsSpace ? String(paddedText.dropFirst()) : paddedText
        if let first = textPart.first, first.isUppercase {
            let lowered = first.lowercased() + textPart.dropFirst()
            paddedText = needsSpace ? " " + lowered : lowered
        }
    }

    finalSegments.append(TextSegment(text: paddedText, type: .dictated))
    isInterimBlocked = false
}
```

**Step 2: Remove old lowercase logic from MenuBarViewModel**

In `MenuBarViewModel.swift`, remove lines 373-377 (in `stopDeepgramStreaming`):

```swift
// DELETE this block:
if isContinueMode {
    if let first = text.first, first.isUppercase {
        text = " " + first.lowercased() + text.dropFirst()
    }
}
```

Same removal in `stopDeepgramREST` lines 429-433.

**Step 3: Commit**

```
git add STTTool/Views/FloatingOverlayWindow.swift STTTool/ViewModels/MenuBarViewModel.swift
git commit -m "feat: apply lowercase toggle per-segment at finalization time"
```

---

### Task 2: Backspace Hotkey

**Files:**
- Modify: `STTTool/Views/FloatingOverlayWindow.swift` (OverlayViewModel + FloatingOverlayWindow public API)
- Modify: `STTTool/ViewModels/MenuBarViewModel.swift` (register hotkey + handler)

**Step 1: Add deleteLastChar to OverlayViewModel**

In `FloatingOverlayWindow.swift`, add method to OverlayViewModel after `deleteLastWord()` (after line 291):

```swift
/// Removes the last character from the last segment. Returns true if a char was removed.
@discardableResult
func deleteLastChar() -> Bool {
    guard !finalSegments.isEmpty else { return false }
    var lastSegment = finalSegments[finalSegments.count - 1]

    if lastSegment.text.isEmpty {
        finalSegments.removeLast()
        return deleteLastChar()
    }

    lastSegment.text.removeLast()
    if lastSegment.text.isEmpty {
        finalSegments.removeLast()
    } else {
        finalSegments[finalSegments.count - 1] = TextSegment(
            text: lastSegment.text,
            type: lastSegment.type
        )
    }
    return true
}
```

**Step 2: Add public API to FloatingOverlayWindow**

After `deleteLastWord()` (line 113), add:

```swift
@discardableResult
func deleteLastChar() -> Bool {
    let removed = overlayViewModel.deleteLastChar()
    updateSize()
    return removed
}
```

**Step 3: Register Backspace hotkey in MenuBarViewModel**

In `registerEditHotkeys()` (after line 548), add:

```swift
// Backspace — delete last character
KeyInterceptor.shared.intercept(keyCode: 51) { [weak self] in
    Task { @MainActor in self?.handleBackspace() }
}
```

In `unregisterEditHotkeys()` (after line 554), add:

```swift
KeyInterceptor.shared.stopIntercepting(keyCode: 51)
```

**Step 4: Add handleBackspace handler**

After `handleDeleteWord()` (after line 597), add:

```swift
private func handleBackspace() {
    guard appState == .streamingRecording else { return }

    guard overlay.isInterimEmpty else {
        overlay.triggerInterimBlocked()
        print("[Backspace] Blocked — interim text present")
        return
    }

    guard overlay.deleteLastChar() else { return }
    syncDeepgramFromOverlay()
    print("[Backspace] Deleted last character")
}
```

**Step 5: Commit**

```
git add STTTool/Views/FloatingOverlayWindow.swift STTTool/ViewModels/MenuBarViewModel.swift
git commit -m "feat: add Backspace hotkey to delete last character during streaming"
```

---

### Task 3: Space Hotkey

**Files:**
- Modify: `STTTool/Views/FloatingOverlayWindow.swift` (OverlayViewModel + FloatingOverlayWindow public API)
- Modify: `STTTool/ViewModels/MenuBarViewModel.swift` (register hotkey + handler)

**Step 1: Add appendSpace to OverlayViewModel**

In `FloatingOverlayWindow.swift`, add method to OverlayViewModel after `deleteLastChar()`:

```swift
/// Appends a space to the last segment. Returns false if no segment or already ends with space.
@discardableResult
func appendSpace() -> Bool {
    guard !finalSegments.isEmpty else { return false }
    let lastSegment = finalSegments[finalSegments.count - 1]
    guard !lastSegment.text.hasSuffix(" ") else { return false }

    finalSegments[finalSegments.count - 1] = TextSegment(
        text: lastSegment.text + " ",
        type: lastSegment.type
    )
    return true
}
```

**Step 2: Add public API to FloatingOverlayWindow**

After `deleteLastChar()`, add:

```swift
@discardableResult
func appendSpace() -> Bool {
    let added = overlayViewModel.appendSpace()
    updateSize()
    return added
}
```

**Step 3: Register Space hotkey in MenuBarViewModel**

In `registerEditHotkeys()`, add:

```swift
// Space — append space to last finalized segment
KeyInterceptor.shared.intercept(keyCode: 49) { [weak self] in
    Task { @MainActor in self?.handleSpace() }
}
```

In `unregisterEditHotkeys()`, add:

```swift
KeyInterceptor.shared.stopIntercepting(keyCode: 49)
```

**Step 4: Add handleSpace handler**

After `handleBackspace()`, add:

```swift
private func handleSpace() {
    guard appState == .streamingRecording else { return }

    guard overlay.isInterimEmpty else {
        overlay.triggerInterimBlocked()
        print("[Space] Blocked — interim text present")
        return
    }

    guard overlay.appendSpace() else { return }
    syncDeepgramFromOverlay()
    print("[Space] Appended space")
}
```

**Step 5: Commit**

```
git add STTTool/Views/FloatingOverlayWindow.swift STTTool/ViewModels/MenuBarViewModel.swift
git commit -m "feat: add Space hotkey to append space to last finalized segment"
```

---

### Task 4: Auto-Expanding Bottom-Anchored Window

**Files:**
- Modify: `STTTool/Views/FloatingOverlayWindow.swift` (positioning, sizing, ScrollView, OverlayViewModel)

**Step 1: Add maxTextHeight to OverlayViewModel**

In OverlayViewModel properties (after line 233), add:

```swift
@Published var maxTextHeight: CGFloat = 250
```

In `reset()` (line 293), add:

```swift
// Don't reset maxTextHeight — it's set by window positioning, not recording state
```

**Step 2: Modify positionOnScreen for bottom-anchored positioning**

Replace `positionOnScreen` (lines 147-154):

```swift
private func positionOnScreen(of targetApp: NSRunningApplication?) {
    let screen = screenForApp(targetApp) ?? NSScreen.main ?? NSScreen.screens.first
    guard let screen else { return }
    let visibleFrame = screen.visibleFrame
    let maxWindowHeight = visibleFrame.height * 0.5
    let headerAndPadding: CGFloat = 50 // header + VStack spacing + padding
    overlayViewModel.maxTextHeight = maxWindowHeight - headerAndPadding

    let width: CGFloat = 400
    let height: CGFloat = 60
    let x = visibleFrame.midX - width / 2
    let y = visibleFrame.origin.y + 40  // 40px above dock/bottom edge
    setFrame(NSRect(x: x, y: y, width: width, height: height), display: false)
}
```

**Step 3: Modify updateSize for bottom-anchored growth**

Replace `updateSize` (lines 197-202):

```swift
private func updateSize() {
    let fittingSize = hostingView.fittingSize
    let width: CGFloat = 400
    let height = max(fittingSize.height, 60)
    let bottomY = frame.origin.y  // preserve bottom edge
    setFrame(NSRect(x: frame.origin.x, y: bottomY, width: width, height: height), display: true)
}
```

**Step 4: Update ScrollView maxHeight in OverlayContentView**

In `segmentedText()` (line 424), replace `.frame(maxHeight: 250)`:

```swift
.frame(maxHeight: viewModel.maxTextHeight)
```

**Step 5: Verify and commit**

Build the project:
```
cd /Users/Denis/dev/tools/stt_tool && xcodegen generate && xcodebuild -scheme STTTool -configuration Debug build 2>&1 | tail -5
```

```
git add STTTool/Views/FloatingOverlayWindow.swift
git commit -m "feat: auto-expanding overlay window anchored at bottom edge"
```

---

### Task 5: Version Bump

**Files:**
- Modify: `project.yml`

**Step 1: Check current version and bump patch**

Read `project.yml`, find `MARKETING_VERSION`, bump the patch version.

**Step 2: Regenerate and commit**

```
xcodegen generate
git add project.yml STTTool.xcodeproj
git commit -m "chore: bump version to X.Y.Z"
```
