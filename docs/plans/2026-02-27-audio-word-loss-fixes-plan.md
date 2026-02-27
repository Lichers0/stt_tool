# Audio Word Loss Fixes — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix word loss during Deepgram streaming transcription — at the start, during, and at the end of recording.

**Architecture:** Four independent fixes touching four files. Each fix is isolated and can be verified separately. Order matters: Task 1 (trivial constant change) first, then Tasks 2-3 (AudioCaptureService + DeepgramService internals), then Task 4 (ViewModel orchestration that depends on both).

**Tech Stack:** Swift 6.0, macOS 14+, AVFoundation, Starscream WebSocket, Deepgram API

**Design doc:** `docs/plans/2026-02-27-audio-word-loss-fixes-design.md`

---

### Task 1: Increase endpointing default (Fix 10d)

**Files:**
- Modify: `STTTool/Utilities/Constants.swift:46` (deepgramModel line area)
- Modify: `STTTool/Services/DeepgramService.swift:50` (endpointing query param)

**Step 1: Change endpointing value**

In `STTTool/Services/DeepgramService.swift`, find the `endpointing` query parameter in `connect()` method (~line 50):

```swift
// BEFORE:
URLQueryItem(name: "endpointing", value: "100"),

// AFTER:
URLQueryItem(name: "endpointing", value: "300"),
```

**Step 2: Build**

Run: `cd /Users/Denis/dev/tools/stt_tool && xcodegen generate && xcodebuild -project STTTool.xcodeproj -scheme STTTool -configuration Debug build 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add STTTool/Services/DeepgramService.swift
git commit -m "fix: increase Deepgram endpointing from 100ms to 300ms

Reduces aggressive segment splitting that caused single words
(especially when switching languages) to be isolated into
separate segments and lost by the speech recognition model."
```

---

### Task 2: Fix race condition on recording stop (Fix 10a)

**Files:**
- Modify: `STTTool/Services/AudioCaptureService.swift:165-173` — `stopStreamingAndGetSamples()`

**Step 1: Reorder operations in stopStreamingAndGetSamples**

In `STTTool/Services/AudioCaptureService.swift`, replace `stopStreamingAndGetSamples()`:

```swift
// BEFORE:
func stopStreamingAndGetSamples() -> [Float] {
    chunkCallback = nil
    isStreamingMode = false
    bufferLock.lock()
    isBuffering = false
    audioBuffer.removeAll()
    bufferLock.unlock()
    return stopRecording()
}

// AFTER:
func stopStreamingAndGetSamples() -> [Float] {
    let samples = stopRecording()    // removeTap first — no more chunks from audio thread
    chunkCallback = nil
    isStreamingMode = false
    bufferLock.lock()
    isBuffering = false
    audioBuffer.removeAll()
    bufferLock.unlock()
    return samples
}
```

Key insight: `stopRecording()` calls `removeTap(onBus: 0)` which stops the audio tap callback. After that, no more chunks will be generated, so it's safe to clear `chunkCallback`. In the old order, `chunkCallback` was cleared while the tap was still running, creating a window where chunks were silently dropped.

**Step 2: Build**

Run: `cd /Users/Denis/dev/tools/stt_tool && xcodebuild -project STTTool.xcodeproj -scheme STTTool -configuration Debug build 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add STTTool/Services/AudioCaptureService.swift
git commit -m "fix: eliminate race condition when stopping streaming recording

Call removeTap before clearing chunkCallback so audio thread
cannot generate chunks that are silently dropped."
```

---

### Task 3: Wait for speech_final instead of fixed 900ms timeout (Fix 10b)

**Files:**
- Modify: `STTTool/Services/DeepgramService.swift` — add finalize continuation, update `stopStreaming()` and `handleMessage()`

**Step 1: Add finalizeContinuation property**

In `STTTool/Services/DeepgramService.swift`, add a new property after the existing `connectContinuation` (~line 33):

```swift
private var connectContinuation: CheckedContinuation<Void, any Error>?
private var finalizeContinuation: CheckedContinuation<Void, Never>?  // ADD THIS
```

**Step 2: Rewrite stopStreaming() to use continuation with timeout**

Replace the `stopStreaming()` method:

```swift
// BEFORE:
func stopStreaming() async -> String {
    guard state == .streaming else {
        print("[Deepgram] stopStreaming skipped, state=\(state)")
        return getResultText(includeInterimFallback: true)
    }

    print("[Deepgram] stopStreaming, chunks sent: \(chunkCount)")
    chunkCount = 0
    state = .idle

    // Ask Deepgram to flush pending interim tokens into final segments.
    socket?.write(string: "{\"type\":\"Finalize\"}")

    // Wait briefly for finalization messages, then fall back to interim if needed.
    try? await Task.sleep(for: .milliseconds(900))

    startKeepAliveTimer()
    startTTLTimer()

    let result = getResultText(includeInterimFallback: true)
    print("[Deepgram] stopStreaming result: \"\(result)\"")
    return result
}

// AFTER:
func stopStreaming() async -> String {
    guard state == .streaming else {
        print("[Deepgram] stopStreaming skipped, state=\(state)")
        return getResultText(includeInterimFallback: true)
    }

    print("[Deepgram] stopStreaming, chunks sent: \(chunkCount)")
    chunkCount = 0
    state = .idle

    // Ask Deepgram to flush pending interim tokens into final segments.
    socket?.write(string: "{\"type\":\"Finalize\"}")

    // Wait for speech_final from Deepgram, with a safety timeout.
    await waitForFinalize(timeout: 3.0)

    startKeepAliveTimer()
    startTTLTimer()

    let result = getResultText(includeInterimFallback: true)
    print("[Deepgram] stopStreaming result: \"\(result)\"")
    return result
}
```

**Step 3: Add waitForFinalize helper method**

Add this method after `stopStreaming()`:

```swift
private func waitForFinalize(timeout: TimeInterval) async {
    await withTaskGroup(of: Void.self) { group in
        group.addTask {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.lock.lock()
                self.finalizeContinuation = continuation
                self.lock.unlock()
            }
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(timeout))
        }
        // Return as soon as EITHER completes (speech_final received OR timeout)
        _ = await group.next()
        group.cancelAll()
        // Clean up continuation if timeout won
        self.lock.lock()
        let pending = self.finalizeContinuation
        self.finalizeContinuation = nil
        self.lock.unlock()
        pending?.resume()
    }
}
```

**Step 4: Resume continuation in handleMessage when speech_final arrives**

In `handleMessage()`, after the existing `if response.isFinal == true` block (~line 294-306), add a check for `speech_final`:

```swift
// EXISTING code for isFinal:
if response.isFinal == true {
    print("[Deepgram] FINAL: \"\(transcript)\"")
    lock.lock()
    if !accumulatedText.isEmpty && !accumulatedText.hasSuffix(" ") {
        accumulatedText += " "
    }
    accumulatedText += transcript
    latestInterimText = ""
    lock.unlock()

    DispatchQueue.main.async {
        self.onFinalResult?(transcript)
    }

    // ADD THIS: Resume finalize continuation when speech_final arrives
    if response.speechFinal == true {
        print("[Deepgram] speech_final received, resuming finalize")
        lock.lock()
        let continuation = finalizeContinuation
        finalizeContinuation = nil
        lock.unlock()
        continuation?.resume()
    }
} else {
    // ... interim handling unchanged
}
```

**Step 5: Clean up continuation on disconnect/error**

In `disconnect()`, add cleanup before existing code:

```swift
func disconnect() {
    // Clean up any pending finalize wait
    lock.lock()
    let pendingFinalize = finalizeContinuation
    finalizeContinuation = nil
    lock.unlock()
    pendingFinalize?.resume()

    stopKeepAliveTimer()
    stopTTLTimer()
    // ... rest unchanged
}
```

Also in the `.error` and `.cancelled` cases of `didReceive(event:)`, add the same cleanup. Find the `.error` case (~line 225):

```swift
case .error(let error):
    print("[Deepgram] WebSocket error: \(String(describing: error))")
    state = .disconnected
    isConnected = false

    // Clean up finalize continuation
    lock.lock()
    let pendingFinalize = finalizeContinuation
    finalizeContinuation = nil
    lock.unlock()
    pendingFinalize?.resume()

    if let continuation = connectContinuation {
        // ... rest unchanged
```

And the `.cancelled` case (~line 237):

```swift
case .cancelled:
    print("[Deepgram] WebSocket cancelled")
    state = .disconnected
    isConnected = false

    // Clean up finalize continuation
    lock.lock()
    let pendingFinalize = finalizeContinuation
    finalizeContinuation = nil
    lock.unlock()
    pendingFinalize?.resume()
```

And `.peerClosed` (~line 248):

```swift
case .peerClosed:
    print("[Deepgram] peer closed")
    state = .disconnected
    isConnected = false

    // Clean up finalize continuation
    lock.lock()
    let pendingFinalize = finalizeContinuation
    finalizeContinuation = nil
    lock.unlock()
    pendingFinalize?.resume()
```

**Step 6: Build**

Run: `cd /Users/Denis/dev/tools/stt_tool && xcodebuild -project STTTool.xcodeproj -scheme STTTool -configuration Debug build 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`

**Step 7: Commit**

```bash
git add STTTool/Services/DeepgramService.swift
git commit -m "fix: wait for speech_final instead of fixed 900ms timeout

After sending Finalize, wait for Deepgram to respond with
speech_final: true (up to 3s safety timeout). This ensures
all final segments are received before reading the result."
```

---

### Task 4: Buffer audio before WebSocket connection (Fix 12)

**Files:**
- Modify: `STTTool/ViewModels/MenuBarViewModel.swift:248-293` — `startDeepgramStreaming()`

**Step 1: Rewrite startDeepgramStreaming to start audio immediately**

Replace the `startDeepgramStreaming()` method:

```swift
// BEFORE:
private func startDeepgramStreaming(apiKey: String, vocabulary: [String]) {
    nonisolated(unsafe) let deepgram = services.deepgramService

    deepgram.onInterimResult = { [weak self] text in
        self?.overlay.updateInterimText(text)
    }

    deepgram.onFinalResult = { [weak self] text in
        self?.overlay.updateFinalSegment(text)
    }

    deepgram.onError = { [weak self] error in
        Task { @MainActor in
            self?.appState = .error(error.localizedDescription)
            self?.overlay.dismissImmediately()
            self?.stopRecordingTimer()
            self?.services.hotKeyService.unregisterModeToggle()
            self?.services.hotKeyService.unregisterCancel()
            self?.resetToIdleAfterDelay()
        }
    }

    Task {
        do {
            if !deepgram.isConnected {
                try await deepgram.connect(apiKey: apiKey, vocabulary: vocabulary)
            }
            deepgram.startStreaming(preserveAccumulatedText: false)

            try services.audioCaptureService.startStreaming { [weak deepgram] chunk in
                deepgram?.sendAudioChunk(chunk)
            }

            overlay.setConnecting(false)
            appState = .streamingRecording
            services.hotKeyService.registerModeToggle()
            services.hotKeyService.registerCancel()
            playStartSound()
            startRecordingTimer()
        } catch {
            appState = .error(error.localizedDescription)
            overlay.dismissImmediately()
            resetToIdleAfterDelay()
        }
    }
}

// AFTER:
private func startDeepgramStreaming(apiKey: String, vocabulary: [String]) {
    nonisolated(unsafe) let deepgram = services.deepgramService

    deepgram.onInterimResult = { [weak self] text in
        self?.overlay.updateInterimText(text)
    }

    deepgram.onFinalResult = { [weak self] text in
        self?.overlay.updateFinalSegment(text)
    }

    deepgram.onError = { [weak self] error in
        Task { @MainActor in
            self?.appState = .error(error.localizedDescription)
            self?.overlay.dismissImmediately()
            self?.stopRecordingTimer()
            self?.services.hotKeyService.unregisterModeToggle()
            self?.services.hotKeyService.unregisterCancel()
            self?.resetToIdleAfterDelay()
        }
    }

    // Start audio capture immediately and buffer chunks while connecting
    do {
        services.audioCaptureService.startBuffering()
        try services.audioCaptureService.startStreaming { _ in }
    } catch {
        appState = .error(error.localizedDescription)
        overlay.dismissImmediately()
        resetToIdleAfterDelay()
        return
    }

    Task {
        do {
            if !deepgram.isConnected {
                try await deepgram.connect(apiKey: apiKey, vocabulary: vocabulary)
            }
            deepgram.startStreaming(preserveAccumulatedText: false)

            // Flush buffered audio and switch to direct sending
            services.audioCaptureService.flushBuffer { [weak deepgram] chunk in
                deepgram?.sendAudioChunk(chunk)
            }
            services.audioCaptureService.replaceChunkCallback { [weak deepgram] chunk in
                deepgram?.sendAudioChunk(chunk)
            }

            overlay.setConnecting(false)
            appState = .streamingRecording
            services.hotKeyService.registerModeToggle()
            services.hotKeyService.registerCancel()
            playStartSound()
            startRecordingTimer()
        } catch {
            _ = services.audioCaptureService.stopStreamingAndGetSamples()
            appState = .error(error.localizedDescription)
            overlay.dismissImmediately()
            resetToIdleAfterDelay()
        }
    }
}
```

Key changes:
1. `startStreaming` + `startBuffering` called BEFORE the async Task (audio starts immediately)
2. After connect, `flushBuffer` sends accumulated audio, then `replaceChunkCallback` switches to direct mode
3. On error inside Task, stop audio capture to clean up
4. Same pattern already used in `confirmVocabularySwitch()` (lines 596-619)

**Step 2: Build**

Run: `cd /Users/Denis/dev/tools/stt_tool && xcodebuild -project STTTool.xcodeproj -scheme STTTool -configuration Debug build 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add STTTool/ViewModels/MenuBarViewModel.swift
git commit -m "fix: buffer audio before WebSocket connection

Start microphone capture immediately on hotkey press and buffer
audio chunks while WebSocket connects. Flush buffered audio
once connected. Prevents loss of first words."
```

---

### Task 5: Manual verification

**Step 1: Build and run**

Run: `cd /Users/Denis/dev/tools/stt_tool && xcodegen generate && xcodebuild -project STTTool.xcodeproj -scheme STTTool -configuration Debug build 2>&1 | tail -5`

**Step 2: Test scenarios**

1. **First words (fix 12):** Press hotkey, immediately say "Первое слово тест". Verify "Первое" is in the transcription.
2. **Last words (fix 10a + 10b):** Say a sentence, press hotkey to stop. Verify last word is not cut off.
3. **Mixed languages (fix 10d):** Say "Открой файл settings и проверь". Verify "settings" is in the transcription.
4. **Vocabulary switch:** During recording, switch vocabulary with arrow keys + Enter. Verify no words lost during switch.
5. **Cancel (Escape):** Start recording, say something, press Escape. Verify no crash and clean state reset.

**Step 3: Check console logs**

Watch for `[AudioCapture]`, `[Deepgram]` log lines. Verify:
- `[Deepgram] speech_final received, resuming finalize` appears when stopping
- No `WARNING: int16ChannelData is nil!` errors
