# SwiftUI Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Align native SwiftUI views with the Next.js prototype design while keeping native macOS controls where appropriate.

**Architecture:** Hybrid approach — custom components (buttons, badges, status indicators, segmented pickers) for visual identity, native controls (TextField, SecureField, ScrollView, List) for platform integration. Navigation restructured from popover-based to tab-based. ViewModels and Services remain unchanged.

**Tech Stack:** Swift 6.0, SwiftUI, macOS 14.0+

**Key structural change:** History and Settings currently open as separate popovers from bottom bar icons. After redesign, they become tabs within the main popover (matching the prototype's PopoverShell with Main/History/Settings tabs at the top).

No intermediate commits. Single commit after all changes are complete.

---

### Task 1: Create Design System

**Files:**
- Create: `STTTool/Views/DesignSystem.swift`

**Step 1: Create the design system file**

```swift
import SwiftUI

// MARK: - Design Tokens

enum DS {

    // MARK: - Colors

    enum Colors {
        // Primary blue - matches prototype oklch(0.55 0.19 255)
        static let primary = Color.accentColor
        static let primarySubtle = Color.accentColor.opacity(0.1)

        // Destructive red
        static let destructive = Color.red
        static let destructiveSubtle = Color.red.opacity(0.1)

        // Status colors
        static let statusIdle = Color.secondary
        static let statusRecording = Color.red
        static let statusTranscribing = Color.orange
        static let statusInserting = Color.accentColor

        // Surfaces
        static let surfaceSubtle = Color(nsColor: .controlBackgroundColor).opacity(0.5)
        static let surfaceHover = Color(nsColor: .controlBackgroundColor).opacity(0.3)

        // Engine badge colors
        static let deepgramBadgeBg = Color.blue.opacity(0.1)
        static let deepgramBadgeFg = Color.blue
        static let whisperkitBadgeBg = Color.green.opacity(0.1)
        static let whisperkitBadgeFg = Color.green

        // Permission states
        static let grantedBg = Color.green.opacity(0.05)
        static let deniedBg = Color.red.opacity(0.05)
    }

    // MARK: - Typography

    enum Typography {
        static let header = Font.system(size: 14, weight: .semibold)
        static let body = Font.system(size: 13)
        static let caption = Font.system(size: 11)
        static let badgeFont = Font.system(size: 11, weight: .medium)
        static let tinyLabel = Font.system(size: 10, weight: .medium)
        static let monoCaption = Font.system(size: 11, weight: .regular, design: .monospaced)
    }

    // MARK: - Spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
    }

    // MARK: - Radius

    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 10
        static let xl: CGFloat = 12
    }

    // MARK: - Layout

    enum Layout {
        static let popoverWidth: CGFloat = 360
        static let iconBoxSize: CGFloat = 32
        static let recordButtonHeight: CGFloat = 44
        static let statusDotSize: CGFloat = 6
        static let smallIconSize: CGFloat = 14
    }

    // MARK: - Animations

    static let pulseRecording = Animation.easeInOut(duration: 0.75).repeatForever(autoreverses: true)
    static let blink = Animation.easeInOut(duration: 0.4).repeatForever(autoreverses: true)
}

// MARK: - AppState Color Extension

extension AppState {
    var statusColor: Color {
        switch self {
        case .idle:
            DS.Colors.statusIdle
        case .recording, .streamingRecording:
            DS.Colors.statusRecording
        case .transcribing:
            DS.Colors.statusTranscribing
        case .inserting:
            DS.Colors.statusInserting
        case .error:
            DS.Colors.destructive
        }
    }
}
```

**Step 2: Add to Xcode project**

Ensure the file is included in the project target. If using XcodeGen (`project.yml`), files in `STTTool/` are auto-included.

---

### Task 2: Create Custom Components

**Files:**
- Create: `STTTool/Views/Components/StatusBadge.swift`
- Create: `STTTool/Views/Components/StatusIndicator.swift`
- Create: `STTTool/Views/Components/RecordButton.swift`
- Create: `STTTool/Views/Components/ActionButton.swift`
- Create: `STTTool/Views/Components/PermissionCard.swift`
- Create: `STTTool/Views/Components/SegmentedPicker.swift`

**Step 1: StatusBadge**

```swift
import SwiftUI

struct StatusBadge: View {
    let text: String
    var foregroundColor: Color = .secondary
    var backgroundColor: Color = Color(nsColor: .quaternarySystemFill)

    var body: some View {
        Text(text)
            .font(DS.Typography.tinyLabel)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(backgroundColor)
            .clipShape(Capsule())
    }
}
```

**Step 2: StatusIndicator**

```swift
import SwiftUI

struct StatusIndicator: View {
    let state: AppState
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(state.statusColor)
            .frame(width: DS.Layout.statusDotSize, height: DS.Layout.statusDotSize)
            .opacity(isPulsing ? 0.5 : 1.0)
            .onChange(of: state.isRecording, initial: true) { _, recording in
                if recording {
                    withAnimation(DS.pulseRecording) { isPulsing = true }
                } else {
                    withAnimation(.easeOut(duration: 0.15)) { isPulsing = false }
                }
            }
    }
}
```

**Step 3: RecordButton**

Reference: prototype `main-view.tsx` lines 89-110. Full-width button, rounded-xl (12pt), height 44pt. Blue idle / red recording.

```swift
import SwiftUI

struct RecordButton: View {
    let isRecording: Bool
    let isDisabled: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: DS.Layout.smallIconSize))
                Text(isRecording ? "Stop Recording" : "Start Recording")
                    .font(.system(size: 13, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: DS.Layout.recordButtonHeight)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.xl)
                    .fill(buttonColor)
            )
            .opacity(isHovering && !isDisabled ? 0.9 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
        .onHover { hovering in isHovering = hovering }
    }

    private var buttonColor: Color {
        isRecording ? DS.Colors.destructive : DS.Colors.primary
    }
}
```

**Step 4: ActionButton**

Reference: prototype ghost buttons like Copy, Delete, Quit, Clear All. Compact, icon + optional text.

```swift
import SwiftUI

struct ActionButton: View {
    enum Style { case ghost, outline, filled }

    let icon: String
    var text: String? = nil
    var style: Style = .ghost
    var destructive: Bool = false
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                if let text {
                    Text(text)
                        .font(.system(size: 11))
                }
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, text != nil ? 8 : 6)
            .padding(.vertical, 4)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovering = hovering }
    }

    private var foregroundColor: Color {
        if destructive && isHovering { return DS.Colors.destructive }
        switch style {
        case .ghost:
            return isHovering ? .primary : .secondary
        case .outline:
            return .primary
        case .filled:
            return .white
        }
    }

    private var background: some ShapeStyle {
        switch style {
        case .ghost:
            return AnyShapeStyle(isHovering ? DS.Colors.surfaceHover : Color.clear)
        case .outline:
            return AnyShapeStyle(isHovering ? DS.Colors.surfaceHover : Color.clear)
        case .filled:
            return AnyShapeStyle(DS.Colors.primary)
        }
    }
}
```

**Step 5: PermissionCard**

Reference: prototype `permissions-screen.tsx` lines 40-77. Card with index/checkmark, icon, label, description, action button.

```swift
import SwiftUI

struct PermissionCard: View {
    let index: Int
    let icon: String
    let title: String
    let description: String
    let granted: Bool
    var actionLabel: String = "Grant"
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            // Status: checkmark or number
            Group {
                if granted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 18))
                } else {
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                            .frame(width: 20, height: 20)
                        Text("\(index)")
                            .font(DS.Typography.tinyLabel)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 24, height: 24)

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

                if !granted, let action {
                    Button(actionLabel, action: action)
                        .controlSize(.small)
                        .padding(.top, 2)
                }
            }
        }
        .padding(DS.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .fill(granted ? DS.Colors.primary.opacity(0.05) : DS.Colors.surfaceSubtle)
        )
    }
}
```

**Step 6: SegmentedPicker**

Reference: prototype settings tabs and engine/mode pickers. Custom segmented control with highlight on active.

```swift
import SwiftUI

struct SegmentedPicker<T: Hashable>: View {
    let items: [(label: String, value: T)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selection = item.value
                    }
                } label: {
                    Text(item.label)
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.md)
                                .fill(selection == item.value
                                      ? DS.Colors.primarySubtle
                                      : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.md)
                                .stroke(selection == item.value
                                        ? DS.Colors.primary.opacity(0.2)
                                        : Color.clear, lineWidth: 1)
                        )
                        .foregroundStyle(selection == item.value
                                         ? DS.Colors.primary
                                         : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .fill(DS.Colors.surfaceSubtle.opacity(0.6))
        )
    }
}
```

---

### Task 3: Create MainView (extract from MenuBarPopoverView)

**Files:**
- Create: `STTTool/Views/MainView.swift`

Extract the main content from current `MenuBarPopoverView` into a new `MainView`. This view shows: header, status, record button, last transcription, footer.

Reference: prototype `main-view.tsx`.

```swift
import SwiftUI

struct MainView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            headerView
            statusView
            RecordButton(
                isRecording: viewModel.appState.isRecording,
                isDisabled: viewModel.appState == .transcribing || viewModel.appState == .inserting,
                action: { viewModel.toggleRecording() }
            )
            lastTranscriptionView
            Divider()
            footerView
        }
        .padding(DS.Spacing.lg)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            HStack(spacing: DS.Spacing.sm) {
                // App icon box
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .fill(DS.Colors.primarySubtle)
                    .frame(width: DS.Layout.iconBoxSize, height: DS.Layout.iconBoxSize)
                    .overlay(
                        Image(systemName: "mic.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(DS.Colors.primary)
                    )
                Text("STT Tool")
                    .font(DS.Typography.header)
            }
            Spacer()
            engineBadge
        }
    }

    @ViewBuilder
    private var engineBadge: some View {
        if viewModel.currentEngine == "deepgram" {
            StatusBadge(
                text: "Deepgram",
                foregroundColor: DS.Colors.deepgramBadgeFg,
                backgroundColor: DS.Colors.deepgramBadgeBg
            )
        } else if viewModel.isLoadingModel {
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("Loading...")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
            }
        } else if viewModel.isModelLoaded {
            StatusBadge(
                text: viewModel.services.transcriptionService.currentModelName,
                foregroundColor: DS.Colors.whisperkitBadgeFg,
                backgroundColor: DS.Colors.whisperkitBadgeBg
            )
        } else if let error = viewModel.modelLoadError {
            Text(error)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Colors.destructive)
                .lineLimit(1)
        }
    }

    // MARK: - Status

    private var statusView: some View {
        HStack(spacing: DS.Spacing.sm) {
            StatusIndicator(state: viewModel.appState)
            Text(viewModel.appState.statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(viewModel.appState.statusColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    // MARK: - Last Transcription

    @ViewBuilder
    private var lastTranscriptionView: some View {
        if let record = viewModel.lastTranscription {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack {
                    Text("LAST TRANSCRIPTION")
                        .font(DS.Typography.tinyLabel)
                        .tracking(0.5)
                        .foregroundStyle(.secondary)
                    Spacer()
                    ActionButton(icon: "doc.on.doc", action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(record.text, forType: .string)
                    })
                }

                HStack(alignment: .top, spacing: DS.Spacing.sm) {
                    if let lang = record.language {
                        StatusBadge(text: lang.uppercased())
                    }
                    Text(record.text)
                        .font(.system(size: 12))
                        .lineLimit(4)
                        .textSelection(.enabled)
                        .foregroundStyle(.primary)
                }
            }
            .padding(DS.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .fill(DS.Colors.surfaceSubtle)
            )
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            if viewModel.currentEngine == "deepgram" {
                ActionButton(
                    icon: "character.book.closed",
                    text: "Vocabularies",
                    action: { VocabularyManagerWindow.showShared() }
                )
            }
            Spacer()
            ActionButton(
                icon: "power",
                text: "Quit",
                destructive: true,
                action: { NSApplication.shared.terminate(nil) }
            )
        }
    }
}
```

---

### Task 4: Restructure MenuBarPopoverView as Tab Shell

**Files:**
- Modify: `STTTool/Views/MenuBarPopoverView.swift`
- Modify: `STTTool/STTToolApp.swift` (minor: pass onModelChange)

The current `MenuBarPopoverView` is replaced with a tab-based shell. History and Settings become tabs instead of separate popovers.

Reference: prototype `popover-shell.tsx`.

**Key change:** PopoverShell manages tab state and creates HistoryViewModel/SettingsViewModel locally.

```swift
import SwiftUI

struct MenuBarPopoverView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @State private var activeTab: PopoverTab = .main

    // Child view models
    @State private var historyVM: HistoryViewModel?
    @State private var settingsVM: SettingsViewModel?

    enum PopoverTab: String, CaseIterable {
        case main, history, settings

        var label: String {
            switch self {
            case .main: "Main"
            case .history: "History"
            case .settings: "Settings"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar at top
            tabBar
                .padding(.horizontal, DS.Spacing.md)
                .padding(.top, DS.Spacing.md)

            // Tab content
            switch activeTab {
            case .main:
                MainView(viewModel: viewModel)
            case .history:
                if let historyVM {
                    HistoryView(viewModel: historyVM)
                }
            case .settings:
                if let settingsVM {
                    SettingsView(viewModel: settingsVM)
                }
            }
        }
        .frame(width: DS.Layout.popoverWidth)
        .onAppear {
            historyVM = HistoryViewModel(
                historyService: viewModel.services.historyService
            )
            settingsVM = SettingsViewModel(
                services: viewModel.services,
                onModelChange: { [weak viewModel] model in
                    viewModel?.reloadModel(name: model)
                }
            )
        }
        .onChange(of: activeTab) { _, newTab in
            if newTab == .history {
                historyVM?.refresh()
            }
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(PopoverTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        activeTab = tab
                    }
                } label: {
                    Text(tab.label)
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.md)
                                .fill(activeTab == tab
                                      ? Color(nsColor: .controlBackgroundColor)
                                      : Color.clear)
                                .shadow(color: activeTab == tab
                                        ? .black.opacity(0.06) : .clear,
                                        radius: 1, y: 1)
                        )
                        .foregroundStyle(activeTab == tab ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .fill(DS.Colors.surfaceSubtle.opacity(0.6))
        )
    }
}
```

**STTToolApp.swift** — no changes needed. The existing `MenuBarPopoverView(viewModel: viewModel)` call stays the same.

---

### Task 5: Restyle HistoryView

**Files:**
- Modify: `STTTool/Views/HistoryView.swift`

Now a tab within the popover (no longer its own popover with fixed frame). Remove `.frame(width: 360, height: 400)`. Use ScrollView with maxHeight.

Reference: prototype `history-view.tsx`.

```swift
import SwiftUI

struct HistoryView: View {
    @ObservedObject var viewModel: HistoryViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .padding(.horizontal, DS.Spacing.lg)
            if viewModel.records.isEmpty {
                emptyState
            } else {
                recordsList
            }
        }
    }

    private var header: some View {
        HStack {
            Text("History")
                .font(DS.Typography.header)
            Spacer()
            if !viewModel.records.isEmpty {
                ActionButton(
                    icon: "trash",
                    text: "Clear All",
                    destructive: true,
                    action: { viewModel.clearAll() }
                )
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.lg)
        .padding(.bottom, DS.Spacing.sm)
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.sm) {
            Spacer()
            Image(systemName: "text.bubble")
                .font(.system(size: 28))
                .foregroundStyle(.secondary.opacity(0.3))
            Text("No transcriptions yet")
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(height: 200)
    }

    private var recordsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.records.enumerated()), id: \.element.id) { index, record in
                    RecordRowView(
                        record: record,
                        onCopy: { viewModel.copyToClipboard(record.text) },
                        onDelete: {
                            if let idx = viewModel.records.firstIndex(where: { $0.id == record.id }) {
                                viewModel.delete(at: IndexSet(integer: idx))
                            }
                        }
                    )
                    if index < viewModel.records.count - 1 {
                        Divider()
                            .padding(.horizontal, DS.Spacing.lg)
                    }
                }
            }
        }
        .frame(maxHeight: 340)
    }
}

// MARK: - Record Row

private struct RecordRowView: View {
    let record: TranscriptionRecord
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(record.text)
                .font(.system(size: 12))
                .lineLimit(3)
                .textSelection(.enabled)
                .foregroundStyle(.primary)

            HStack {
                if let lang = record.language {
                    StatusBadge(text: lang.uppercased())
                }
                Text(record.date, style: .relative)
                    .font(DS.Typography.tinyLabel)
                    .foregroundStyle(.secondary)
                Text(record.modelName)
                    .font(DS.Typography.tinyLabel)
                    .foregroundStyle(.secondary.opacity(0.6))

                Spacer()

                HStack(spacing: 2) {
                    ActionButton(icon: "doc.on.doc", action: onCopy)
                    ActionButton(icon: "trash", destructive: true, action: onDelete)
                }
                .opacity(isHovering ? 1 : 0)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .background(isHovering ? DS.Colors.surfaceHover : Color.clear)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovering = hovering }
        }
    }
}
```

---

### Task 6: Restyle SettingsView

**Files:**
- Modify: `STTTool/Views/SettingsView.swift`

Now a tab within the popover. Replace native segmented pickers with `SegmentedPicker`. Add sub-tabs (General/Engine/Permissions). Remove `.frame(width: 340)`.

Reference: prototype `settings-view.tsx`.

**Key changes:**
- Add sub-tab navigation (General / Engine / Permissions) via `SegmentedPicker`
- Engine selection via `SegmentedPicker` instead of native `Picker(.segmented)`
- Deepgram mode via `SegmentedPicker`
- Hotkey/mode-toggle displayed as styled kbd-like badges
- Model selection with radio-style list rows
- Permissions tab with colored status cards

```swift
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var permissionsService: PermissionsServiceProtocol
    @State private var activeSubTab = "general"

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        self._permissionsService = State(initialValue: viewModel.permissionsService)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            // Header + sub-tabs
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                Text("Settings")
                    .font(DS.Typography.header)

                SegmentedPicker(
                    items: [
                        ("General", "general"),
                        ("Engine", "engine"),
                        ("Permissions", "permissions")
                    ],
                    selection: $activeSubTab
                )
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.lg)

            // Content
            ScrollView {
                switch activeSubTab {
                case "general":
                    generalTab
                case "engine":
                    engineTab
                case "permissions":
                    permissionsTab
                default:
                    EmptyView()
                }
            }
            .frame(maxHeight: 360)
        }
        .padding(.bottom, DS.Spacing.lg)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xl) {
            // Hotkey
            sectionLabel("HOTKEY")
            HotKeyRecorderView(viewModel: viewModel)

            Divider()

            // Mode Toggle Key
            sectionLabel("MODE TOGGLE KEY")
            HStack {
                kbdBadge(viewModel.modeToggleKeyDisplayString)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.xs)
    }

    // MARK: - Engine Tab

    private var engineTab: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xl) {
            // Engine picker
            sectionLabel("TRANSCRIPTION ENGINE")
            SegmentedPicker(
                items: [
                    ("Deepgram", "deepgram"),
                    ("WhisperKit", "whisperkit")
                ],
                selection: $viewModel.selectedEngine
            )
            .onChange(of: viewModel.selectedEngine) { _, newValue in
                viewModel.setEngine(newValue)
            }

            if viewModel.selectedEngine == "deepgram" {
                Divider()
                deepgramSettings
            }

            if viewModel.selectedEngine == "whisperkit" {
                Divider()
                whisperSettings
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.xs)
    }

    private var deepgramSettings: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xl) {
            // Mode
            sectionLabel("MODE")
            SegmentedPicker(
                items: [("Streaming", "streaming"), ("REST", "rest")],
                selection: $viewModel.deepgramMode
            )
            .onChange(of: viewModel.deepgramMode) { _, newValue in
                viewModel.setDeepgramMode(newValue)
            }

            Divider()

            // API Key
            sectionLabel("API KEY")
            apiKeySection

            Divider()

            // Vocabulary
            sectionLabel("VOCABULARY")
            ActionButton(
                icon: "character.book.closed",
                text: "Manage Vocabularies...",
                style: .outline,
                action: { VocabularyManagerWindow.showShared() }
            )
            Text("Create themed vocabularies to improve recognition accuracy for specialized terms.")
                .font(DS.Typography.tinyLabel)
                .foregroundStyle(.secondary)
        }
    }

    private var whisperSettings: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            sectionLabel("MODEL")
            ForEach(viewModel.availableModels, id: \.self) { model in
                Button(action: { viewModel.selectModel(model) }) {
                    HStack {
                        Image(systemName: model == viewModel.selectedModel
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(model == viewModel.selectedModel
                                             ? DS.Colors.primary : .secondary)
                            .font(.system(size: 14))
                        Text(viewModel.modelDescriptions[model] ?? model)
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, DS.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.lg)
                            .fill(model == viewModel.selectedModel
                                  ? DS.Colors.primary.opacity(0.05)
                                  : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - API Key Section

    @State private var newAPIKey = ""
    @State private var isEditingKey = false

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            if viewModel.hasAPIKey && !isEditingKey {
                HStack {
                    Text("............")
                        .font(DS.Typography.monoCaption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.md)
                                .fill(DS.Colors.surfaceSubtle)
                        )
                    ActionButton(
                        icon: "pencil",
                        text: "Change",
                        style: .outline,
                        action: { isEditingKey = true }
                    )
                }
            } else {
                HStack {
                    SecureField("Enter API key...", text: $newAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .font(DS.Typography.caption)
                    Button(viewModel.isValidatingKey ? "..." : "Save") {
                        Task {
                            await viewModel.saveAPIKey(newAPIKey)
                            newAPIKey = ""
                            isEditingKey = false
                        }
                    }
                    .controlSize(.small)
                    .disabled(newAPIKey.isEmpty || viewModel.isValidatingKey)
                    if isEditingKey {
                        Button("Cancel") { isEditingKey = false; newAPIKey = "" }
                            .controlSize(.small)
                    }
                }
                if let error = viewModel.apiKeyError {
                    Text(error)
                        .font(DS.Typography.tinyLabel)
                        .foregroundStyle(DS.Colors.destructive)
                }
            }
        }
    }

    // MARK: - Permissions Tab

    private var permissionsTab: some View {
        VStack(spacing: DS.Spacing.md) {
            ForEach([
                ("microphone", "Microphone", permissionsService.isMicrophoneGranted),
                ("accessibility", "Accessibility", permissionsService.isAccessibilityGranted)
            ], id: \.0) { (id, label, granted) in
                HStack {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(granted ? .green : .red)
                            .font(.system(size: 14))
                        Text(label)
                            .font(.system(size: 12, weight: .medium))
                    }
                    Spacer()
                    if !granted {
                        Button(id == "microphone" ? "Grant" : "Open Settings") {
                            if id == "microphone" {
                                Task { _ = await permissionsService.requestMicrophoneAccess() }
                            } else {
                                permissionsService.openAccessibilitySettings()
                            }
                        }
                        .controlSize(.small)
                    }
                }
                .padding(DS.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.lg)
                        .fill(granted ? DS.Colors.grantedBg : DS.Colors.deniedBg)
                )
            }

            ActionButton(
                icon: "arrow.clockwise",
                text: "Refresh Status",
                action: { permissionsService.checkPermissions() }
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.xs)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(DS.Typography.tinyLabel)
            .tracking(0.5)
            .foregroundStyle(.secondary)
    }

    private func kbdBadge(_ text: String) -> some View {
        Text(text)
            .font(DS.Typography.monoCaption)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xs)
            .background(DS.Colors.surfaceSubtle)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
    }
}

// MARK: - Hotkey Recorder (kept from original, minimal style changes)

private struct HotKeyRecorderView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Button(action: toggleRecording) {
                Text(isRecording ? "Type shortcut..." : viewModel.hotKeyDisplayString)
                    .font(DS.Typography.monoCaption)
                    .frame(minWidth: 120)
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, DS.Spacing.xs)
                    .background(isRecording
                                ? DS.Colors.primarySubtle
                                : DS.Colors.surfaceSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.sm)
                            .stroke(isRecording ? DS.Colors.primary : Color(nsColor: .separatorColor),
                                    lineWidth: isRecording ? 1 : 0.5)
                    )
            }
            .buttonStyle(.plain)

            if !isRecording {
                ActionButton(icon: "arrow.counterclockwise", text: "Reset") {
                    viewModel.resetHotKey()
                }
            }
        }
        .onDisappear { stopRecording() }
    }

    private func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        isRecording = true
        viewModel.suspendHotKey()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .subtracting(.capsLock)
            let requiredMods: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
            guard !mods.intersection(requiredMods).isEmpty else { return nil }
            viewModel.hotKeyKeyCode = UInt32(event.keyCode)
            viewModel.hotKeyModifiers = UInt32(mods.rawValue)
            viewModel.saveHotKey()
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        viewModel.resumeHotKey()
    }
}
```

---

### Task 7: Restyle StartupGuardianView

**Files:**
- Modify: `STTTool/Views/StartupGuardianView.swift`

Replace manual permission rows with `PermissionCard` components. Add app icon box at top (matching prototype).

Reference: prototype `permissions-screen.tsx`.

The structure stays the same — reuse `PermissionCard` component. Update visual styling.

```swift
import SwiftUI

struct StartupGuardianView: View {
    let permissionsService: PermissionsServiceProtocol
    let keychainService: KeychainServiceProtocol
    let onComplete: () -> Void

    @State private var micGranted = false
    @State private var accessibilityGranted = false
    @State private var keychainStatus: KeychainProbeStatus = .notConfigured

    var body: some View {
        VStack(spacing: DS.Spacing.xl) {
            // Icon + title
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
                    description: "Required to record your speech.",
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
                    description: "Required to paste text into other apps.",
                    granted: accessibilityGranted,
                    actionLabel: "Open Settings",
                    action: { permissionsService.openAccessibilitySettings() }
                )
                if !accessibilityGranted {
                    Text("Enable STTTool in the list, then return here.")
                        .font(DS.Typography.tinyLabel)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 36)
                }

                keychainCard
            }

            // Continue button
            RecordButton(
                isRecording: false,
                isDisabled: !micGranted || !accessibilityGranted,
                action: {
                    permissionsService.stopAccessibilityPolling()
                    onComplete()
                }
            )
            // Override: show "Continue" text instead of "Start Recording"
            .hidden()
            .overlay {
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
        }
        .padding(DS.Spacing.xxl)
        .frame(width: DS.Layout.popoverWidth)
        .onAppear {
            micGranted = permissionsService.isMicrophoneGranted
            accessibilityGranted = permissionsService.isAccessibilityGranted
            permissionsService.startAccessibilityPolling()
            permissionsService.probeKeychainAccess(using: keychainService)
            keychainStatus = permissionsService.keychainStatus
        }
        .onDisappear { permissionsService.stopAccessibilityPolling() }
        .onChange(of: permissionsService.isAccessibilityGranted) { _, newValue in
            accessibilityGranted = newValue
        }
        .onChange(of: permissionsService.keychainStatus) { _, newValue in
            keychainStatus = newValue
        }
    }

    @ViewBuilder
    private var keychainCard: some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            Group {
                switch keychainStatus {
                case .accessible:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 18))
                case .notConfigured:
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                            .frame(width: 20, height: 20)
                        Text("3")
                            .font(DS.Typography.tinyLabel)
                            .foregroundStyle(.secondary)
                    }
                case .denied:
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.red)
                        .font(.system(size: 18))
                }
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("Keychain")
                        .font(.system(size: 13, weight: .medium))
                }
                Text(keychainDescription)
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                if keychainStatus == .denied {
                    Button("Retry") {
                        permissionsService.probeKeychainAccess(using: keychainService)
                        keychainStatus = permissionsService.keychainStatus
                    }
                    .controlSize(.small)
                    .padding(.top, 2)
                }
            }
        }
        .padding(DS.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .fill(keychainStatus == .accessible
                      ? DS.Colors.primary.opacity(0.05)
                      : DS.Colors.surfaceSubtle)
        )
    }

    private var keychainDescription: String {
        switch keychainStatus {
        case .accessible: "Deepgram API key accessible."
        case .notConfigured: "Not configured — set up in Settings later."
        case .denied: "Access denied. Press Always Allow when prompted."
        }
    }
}
```

---

### Task 8: Style VocabularyManagerWindow

**Files:**
- Modify: `STTTool/Views/VocabularyManagerWindow.swift`

Minimal style refinements — apply DS tokens to existing structure. Keep `NavigationSplitView`, `List`, and overall architecture unchanged.

**Changes:**
- Use `DS.Typography` for fonts
- Use `DS.Colors` for status indicators
- Use `DS.Spacing` and `DS.Radius` for padding/corners
- Use `ActionButton` for sidebar toolbar buttons and detail actions
- Use `StatusBadge`-like styling for term counts
- Apply hover effects where appropriate

The changes are spread across existing views. Apply `DS` tokens to existing code without structural changes.

Key replacements:
1. Sidebar toolbar: replace plain icon buttons with `ActionButton` components
2. Detail header: use `DS.Typography.header` for vocabulary name
3. Term count footer: use `DS.Typography.tinyLabel`
4. Footer picker: replace native `Picker(.segmented)` with `SegmentedPicker`
5. Active indicator: use `DS.Colors.primary` instead of `.blue`

---

### Task 9: Update FloatingOverlayWindow

**Files:**
- Modify: `STTTool/Views/FloatingOverlayWindow.swift`

Apply DS tokens and match prototype styling. The window structure stays unchanged (NSPanel + NSHostingView + VisualEffectBlur).

**Changes to `OverlayContentView`:**
- Mode indicator: use `StatusBadge`-like styling
- Vocabulary name: use `DS.Typography`
- Timer: use `DS.Typography.monoCaption`
- Border radius: `DS.Radius.xl` (12pt, matching prototype `rounded-2xl`)
- Interim text: `.secondary` color (muted)
- Placeholder: "Listening..." in italic `.secondary.opacity(0.5)`
- Blink animation: use `DS.blink`

Replace hardcoded colors/sizes with `DS` tokens. The `VisualEffectBlur` wrapper stays as-is since it handles NSPanel blur correctly.

---

### Build & Verify

After all tasks complete:

**Step 1:** Build the project

```bash
cd /Users/Denis/dev/tools/stt_tool && xcodebuild -project STTTool.xcodeproj -scheme STTTool -configuration Debug build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED

**Step 2:** Fix any compile errors. Common issues:
- Missing imports
- Type mismatches between `SegmentedPicker` generic and binding types
- `AnyShapeStyle` availability on macOS 14
- `SettingsViewModel.permissionsService` accessibility (may need to make it `internal` or add a computed property)

**Step 3:** Visual verification — launch the app from Xcode, check each tab visually.
