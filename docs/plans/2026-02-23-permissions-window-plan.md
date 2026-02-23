# Permissions Window Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace in-popover StartupGuardianView with a standalone NSWindow that opens automatically at launch when permissions are missing.

**Architecture:** New `PermissionsWindow` (NSWindow + SwiftUI hosting) opens at app launch if any required permission is missing. Menu bar icon click focuses this window instead of opening the popover. After all permissions granted and user clicks "Continue", window closes and app activates normally.

**Tech Stack:** Swift 6.0, SwiftUI, AppKit (NSWindow), existing DesignSystem tokens

**Design doc:** `docs/plans/2026-02-23-permissions-window-design.md`

---

### Task 1: Add `isWaitingForAccessibility` to PermissionsService

**Files:**
- Modify: `STTTool/Services/PermissionsService.swift`
- Modify: `STTTool/Services/ServiceContainer.swift` (protocol)

**Step 1: Add property to protocol**

In `STTTool/Services/ServiceContainer.swift`, add to `PermissionsServiceProtocol`:

```swift
var isWaitingForAccessibility: Bool { get }
```

**Step 2: Implement in PermissionsService**

In `STTTool/Services/PermissionsService.swift`:

1. Add published property:
```swift
@Published private(set) var isWaitingForAccessibility = false
```

2. Modify `startAccessibilityPolling()` — set `isWaitingForAccessibility = true` at the start.

3. Modify `stopAccessibilityPolling()` — set `isWaitingForAccessibility = false`.

4. In the polling timer callback, when `AXIsProcessTrusted()` returns true — call `stopAccessibilityPolling()` automatically (so polling self-terminates on grant).

Full updated methods:
```swift
func startAccessibilityPolling() {
    stopAccessibilityPolling()
    isWaitingForAccessibility = true
    accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
        Task { @MainActor in
            guard let self else { return }
            let granted = AXIsProcessTrusted()
            self.isAccessibilityGranted = granted
            if granted {
                self.stopAccessibilityPolling()
            }
        }
    }
}

func stopAccessibilityPolling() {
    accessibilityTimer?.invalidate()
    accessibilityTimer = nil
    isWaitingForAccessibility = false
}
```

**Step 3: Build**

Run: `cd /Users/Denis/dev/tools/stt_tool && xcodebuild -project STTTool.xcodeproj -scheme STTTool -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add STTTool/Services/PermissionsService.swift STTTool/Services/ServiceContainer.swift
git commit -m "feat: add isWaitingForAccessibility to PermissionsService"
```

---

### Task 2: Update PermissionCard to support waiting state

**Files:**
- Modify: `STTTool/Views/Components/PermissionCard.swift`

**Step 1: Add `isWaiting` parameter and spinner UI**

Add optional `isWaiting` parameter (default `false`). When `isWaiting == true && !granted`, show a `ProgressView` spinner instead of the number circle, and replace the action button with "Waiting for permission..." text.

```swift
struct PermissionCard: View {
    let index: Int
    let icon: String
    let title: String
    let description: String
    let granted: Bool
    var isWaiting: Bool = false
    var actionLabel: String = "Grant"
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            // Status indicator
            ZStack {
                if granted {
                    Image(systemName: "checkmark.circle.fill")
                        .resizable()
                        .frame(width: 22, height: 22)
                        .foregroundStyle(.green)
                } else if isWaiting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Circle()
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1.5)
                    Text("\(index)")
                        .font(DS.Typography.tinyLabel)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                }

                Text(description)
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)

                if isWaiting && !granted {
                    Text("Waiting for permission...")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.orange)
                } else if !granted, let action {
                    Button(actionLabel, action: action)
                        .controlSize(.small)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .fill(granted ? DS.Colors.primary.opacity(0.05) : DS.Colors.surfaceSubtle)
        )
    }
}
```

**Step 2: Build**

Run: `cd /Users/Denis/dev/tools/stt_tool && xcodebuild -project STTTool.xcodeproj -scheme STTTool -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add STTTool/Views/Components/PermissionCard.swift
git commit -m "feat: add waiting/spinner state to PermissionCard"
```

---

### Task 3: Create PermissionsWindow

**Files:**
- Create: `STTTool/Views/PermissionsWindow.swift`

**Step 1: Create the file**

This file contains two things:
1. `PermissionsWindowController` — manages NSWindow lifecycle
2. `PermissionsSetupView` — SwiftUI content (replaces StartupGuardianView)

```swift
import AppKit
import SwiftUI

// MARK: - Window Controller

@MainActor
final class PermissionsWindowController {
    private var window: NSWindow?

    func show(
        permissionsService: PermissionsServiceProtocol,
        keychainService: KeychainServiceProtocol,
        onComplete: @escaping () -> Void
    ) {
        guard window == nil else {
            focus()
            return
        }

        let view = PermissionsSetupView(
            permissionsService: permissionsService,
            keychainService: keychainService,
            onComplete: { [weak self] in
                onComplete()
                self?.close()
            }
        )

        let hostingView = NSHostingView(rootView: view)
        hostingView.setFrameSize(NSSize(width: 400, height: 380))

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 380),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        w.title = "STT Tool Setup"
        w.contentView = hostingView
        w.center()
        w.isReleasedWhenClosed = false
        w.level = .floating
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func focus() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    func close() {
        window?.close()
        window = nil
    }
}

// MARK: - SwiftUI View

struct PermissionsSetupView: View {
    let permissionsService: PermissionsServiceProtocol
    let keychainService: KeychainServiceProtocol
    let onComplete: () -> Void

    @State private var micGranted = false
    @State private var accessibilityGranted = false
    @State private var accessibilityWaiting = false
    @State private var keychainStatus: KeychainProbeStatus = .notConfigured

    var body: some View {
        VStack(spacing: DS.Spacing.xl) {
            // Header
            VStack(spacing: DS.Spacing.sm) {
                RoundedRectangle(cornerRadius: DS.Spacing.lg)
                    .fill(DS.Colors.primarySubtle)
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "mic.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(DS.Colors.primary)
                    )
                Text("STT Tool Setup")
                    .font(.system(size: 15, weight: .semibold))
                Text("Grant permissions to enable voice transcription.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Permission cards
            VStack(spacing: DS.Spacing.md) {
                PermissionCard(
                    index: 1,
                    icon: "mic.fill",
                    title: "Microphone",
                    description: micGranted
                        ? "Microphone access granted."
                        : "Required to record your speech.",
                    granted: micGranted,
                    actionLabel: "Grant Access",
                    action: {
                        Task { micGranted = await permissionsService.requestMicrophoneAccess() }
                    }
                )

                PermissionCard(
                    index: 2,
                    icon: "accessibility",
                    title: "Accessibility",
                    description: accessibilityGranted
                        ? "Accessibility access granted."
                        : "Required to paste text into other apps.",
                    granted: accessibilityGranted,
                    isWaiting: accessibilityWaiting,
                    actionLabel: "Open Settings",
                    action: {
                        permissionsService.openAccessibilitySettings()
                        permissionsService.startAccessibilityPolling()
                    }
                )

                PermissionCard(
                    index: 3,
                    icon: "key.fill",
                    title: "Keychain",
                    description: keychainDescription,
                    granted: keychainStatus == .accessible,
                    actionLabel: "Allow Access",
                    action: keychainStatus == .denied ? {
                        permissionsService.probeKeychainAccess(using: keychainService)
                        keychainStatus = permissionsService.keychainStatus
                    } : nil
                )
            }

            // Continue button
            Button {
                permissionsService.stopAccessibilityPolling()
                onComplete()
            } label: {
                HStack(spacing: DS.Spacing.sm) {
                    Text("Continue")
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12))
                }
                .frame(maxWidth: .infinity)
                .frame(height: DS.Layout.recordButtonHeight)
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.xl)
                        .fill(DS.Colors.primary)
                )
            }
            .buttonStyle(.plain)
            .disabled(!micGranted || !accessibilityGranted)
            .opacity(!micGranted || !accessibilityGranted ? 0.5 : 1.0)
        }
        .padding(DS.Spacing.xxl)
        .onAppear {
            micGranted = permissionsService.isMicrophoneGranted
            accessibilityGranted = permissionsService.isAccessibilityGranted
            accessibilityWaiting = permissionsService.isWaitingForAccessibility
            permissionsService.probeKeychainAccess(using: keychainService)
            keychainStatus = permissionsService.keychainStatus
        }
        .onChange(of: permissionsService.isAccessibilityGranted) { _, newValue in
            accessibilityGranted = newValue
        }
        .onChange(of: permissionsService.isWaitingForAccessibility) { _, newValue in
            accessibilityWaiting = newValue
        }
        .onChange(of: permissionsService.keychainStatus) { _, newValue in
            keychainStatus = newValue
        }
    }

    private var keychainDescription: String {
        switch keychainStatus {
        case .accessible: "Deepgram API key accessible."
        case .notConfigured: "Not configured yet — set up in Settings later."
        case .denied: "Access denied. Press Always Allow when prompted."
        }
    }
}
```

**Step 2: Add file to project**

Run: `cd /Users/Denis/dev/tools/stt_tool && xcodegen generate`

**Step 3: Build**

Run: `cd /Users/Denis/dev/tools/stt_tool && xcodebuild -project STTTool.xcodeproj -scheme STTTool -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add STTTool/Views/PermissionsWindow.swift project.yml
git commit -m "feat: add standalone PermissionsWindow with NSWindow wrapper"
```

---

### Task 4: Rewire STTToolApp to use PermissionsWindow

**Files:**
- Modify: `STTTool/STTToolApp.swift`

**Step 1: Replace StartupGuardianView with PermissionsWindowController**

Replace the entire file with:

```swift
import SwiftUI

@main
struct STTToolApp: App {
    @State private var services = ServiceContainer()
    @State private var viewModel: MenuBarViewModel?
    @State private var permissionsReady = false
    private let permissionsWindow = PermissionsWindowController()

    var body: some Scene {
        MenuBarExtra {
            if let viewModel {
                if permissionsReady {
                    MenuBarPopoverView(viewModel: viewModel)
                } else {
                    // Minimal view — clicking menu bar icon focuses the permissions window
                    VStack(spacing: DS.Spacing.md) {
                        Text("Setup required")
                            .font(DS.Typography.body)
                            .foregroundStyle(.secondary)
                        Button("Open Setup Window") {
                            permissionsWindow.focus()
                        }
                        .controlSize(.small)
                    }
                    .padding(DS.Spacing.xl)
                    .frame(width: 200)
                }
            } else {
                ProgressView("Loading...")
                    .padding()
                    .onAppear { initializeApp() }
            }
        } label: {
            Image(systemName: viewModel?.appState.systemImage ?? "mic")
        }
        .menuBarExtraStyle(.window)
    }

    private func initializeApp() {
        let vm = MenuBarViewModel(services: services)
        viewModel = vm

        services.permissionsService.checkPermissions()
        if services.permissionsService.allRequiredPermissionsGranted {
            permissionsReady = true
            vm.activate()
            loadModelIfNeeded(vm: vm)
        } else {
            permissionsWindow.show(
                permissionsService: services.permissionsService,
                keychainService: services.keychainService,
                onComplete: { [vm] in
                    permissionsReady = true
                    vm.activate()
                    loadModelIfNeeded(vm: vm)
                }
            )
        }
    }

    private func loadModelIfNeeded(vm: MenuBarViewModel) {
        let engine = UserDefaults.standard.string(
            forKey: Constants.deepgramEngineKey
        ) ?? Constants.defaultEngine
        if engine == "whisperkit" {
            vm.loadModelAtLaunch()
        }
    }
}
```

Key changes:
- `PermissionsWindowController` stored as property
- On launch with missing permissions → `permissionsWindow.show(...)`
- Menu bar popover when not ready → small "Setup required" view with button to focus the window
- No more `StartupGuardianView` reference

**Step 2: Build**

Run: `cd /Users/Denis/dev/tools/stt_tool && xcodebuild -project STTTool.xcodeproj -scheme STTTool -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add STTTool/STTToolApp.swift
git commit -m "feat: open standalone permissions window at launch"
```

---

### Task 5: Delete StartupGuardianView

**Files:**
- Delete: `STTTool/Views/StartupGuardianView.swift`

**Step 1: Delete file**

```bash
rm STTTool/Views/StartupGuardianView.swift
```

**Step 2: Regenerate project**

Run: `cd /Users/Denis/dev/tools/stt_tool && xcodegen generate`

**Step 3: Build**

Run: `cd /Users/Denis/dev/tools/stt_tool && xcodebuild -project STTTool.xcodeproj -scheme STTTool -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED (no references to StartupGuardianView remain)

**Step 4: Commit**

```bash
git add -A
git commit -m "refactor: remove StartupGuardianView, replaced by PermissionsWindow"
```

---

### Task 6: Manual smoke test

**No code changes — verification only.**

**Step 1: Test with all permissions granted**

1. Build and run the app
2. Verify: no permissions window appears
3. Verify: popover works normally
4. Verify: hotkeys work

**Step 2: Test with missing Accessibility**

1. Revoke Accessibility in System Settings > Privacy > Accessibility
2. Restart the app
3. Verify: permissions window appears automatically
4. Verify: clicking menu bar icon shows "Setup required" + button to focus window
5. Click "Open Settings" on Accessibility row
6. Verify: spinner + "Waiting for permission..." appears
7. Grant Accessibility in System Settings
8. Verify: within ~2 seconds, checkmark appears with animation
9. Click "Continue"
10. Verify: window closes, popover works, hotkeys registered

**Step 3: Test window cannot be closed**

1. With permissions window open, try Cmd+W
2. Verify: window stays open (no close button, not closable)

**Step 4: Test Keychain**

1. If keychain has no API key → verify "Not configured yet" text, Continue not blocked
2. If keychain has key → verify "Deepgram API key accessible" with checkmark

---

### Task 7: Bump version

**Files:**
- Modify: `project.yml`

**Step 1: Bump build number**

In `project.yml`, change `CURRENT_PROJECT_VERSION` from `"2"` to `"3"`.

Ask user if MARKETING_VERSION should also change (1.2.0 → 1.3.0).

**Step 2: Regenerate project**

Run: `cd /Users/Denis/dev/tools/stt_tool && xcodegen generate`

**Step 3: Commit**

```bash
git add project.yml
git commit -m "chore: bump build version to 3"
```
