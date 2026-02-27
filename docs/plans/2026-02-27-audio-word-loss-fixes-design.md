# Audio Word Loss Fixes Design

## Problems

### Problem 12: Audio not captured before WebSocket connection
When user presses hotkey and starts speaking, microphone only turns on AFTER WebSocket connects (~200-500ms). First words are lost.

### Problem 10a: Race condition on recording stop
In `stopStreamingAndGetSamples()`, `chunkCallback` is set to nil before `removeTap()`. Audio tap runs on a separate thread and generates 1-2 chunks between these steps — those chunks are silently dropped.

### Problem 10b: Fixed 900ms Finalize timeout
After sending `{"type":"Finalize"}` to Deepgram, the app waits exactly 900ms. On slow connections this is not enough; on fast connections this adds unnecessary latency.

### Problem 10d: Aggressive endpointing (100ms)
`endpointing: 100` splits speech into segments on 100ms pauses. When switching languages (e.g. Russian to English), micro-pauses isolate single words into separate segments. Short isolated segments in a different language are often not recognized by Deepgram's `language: multi` mode.

## Solutions

### Fix 12: Buffer audio before WebSocket connection
**File:** `MenuBarViewModel.swift` — `startDeepgramStreaming()`

Current flow:
```
hotkey -> connect(~400ms) -> startStreaming -> startAudio
```

New flow:
```
hotkey -> startAudio + startBuffering -> connect(~400ms) -> flush + stream
```

Use existing `AudioCaptureService` buffering infrastructure (`startBuffering()`, `flushBuffer()`, `replaceChunkCallback()`) — already implemented for vocabulary switching.

Changes:
1. Call `audioCaptureService.startStreaming()` with a no-op callback BEFORE `deepgram.connect()`
2. Call `audioCaptureService.startBuffering()` to accumulate chunks
3. After connect + startStreaming, call `flushBuffer()` to send accumulated audio
4. Call `replaceChunkCallback()` to switch to direct sending

### Fix 10a: Swap removeTap and callback cleanup order
**File:** `AudioCaptureService.swift` — `stopStreamingAndGetSamples()`

Current:
```swift
chunkCallback = nil       // step 1: stop sending
return stopRecording()    // step 2: removeTap + stop engine
```

New:
```swift
let samples = stopRecording()  // step 1: removeTap (no more chunks generated)
chunkCallback = nil            // step 2: safe to clear now
return samples
```

### Fix 10b: Wait for speech_final instead of fixed timeout
**File:** `DeepgramService.swift` — `stopStreaming()` + `handleMessage()`

Current:
```swift
socket?.write(string: "{\"type\":\"Finalize\"}")
try? await Task.sleep(for: .milliseconds(900))
return getResultText(...)
```

New:
- Add `finalizeContinuation: CheckedContinuation<Void, Never>?`
- In `stopStreaming()`: send Finalize, then `await` the continuation with 3s timeout
- In `handleMessage()`: when receiving a message with `speech_final: true` after Finalize, resume the continuation
- Safety timeout: if no `speech_final` arrives within 3 seconds, proceed with what we have

### Fix 10d: Increase endpointing default
**File:** `Constants.swift`

Change `endpointing` query parameter from `"100"` to `"300"`.

This reduces aggressive segment splitting, keeping mixed-language words within the same segment context for better recognition.

## Files Changed
- `MenuBarViewModel.swift` — reorder audio start + add buffering (fix 12)
- `AudioCaptureService.swift` — swap stop order (fix 10a)
- `DeepgramService.swift` — async Finalize completion (fix 10b)
- `Constants.swift` — endpointing value (fix 10d)

## Testing
- Verify first words are captured when speaking immediately after hotkey press
- Verify no words lost at the end of recording
- Verify mixed Russian/English sentences transcribe completely
- Verify vocabulary switching still works (uses same buffering mechanism)
