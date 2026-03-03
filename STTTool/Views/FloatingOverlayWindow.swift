import AppKit
import SwiftUI

final class FloatingOverlayWindow: NSPanel {

    private let hostingView: NSHostingView<OverlayContentView>
    private let overlayViewModel = OverlayViewModel()
    private var screenOriginY: CGFloat = 0

    init() {
        hostingView = NSHostingView(rootView: OverlayContentView(viewModel: overlayViewModel))

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 60),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false

        contentView = hostingView
    }

    // MARK: - Public API

    func showForRecording(targetApp: NSRunningApplication? = nil) {
        overlayViewModel.reset()
        positionOnScreen(of: targetApp)
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.animator().alphaValue = 1
        }
    }

    func updateInterimText(_ text: String) {
        overlayViewModel.interimText = text
        updateSize()
    }

    func updateFinalSegment(_ text: String) {
        overlayViewModel.interimText = ""
        overlayViewModel.appendFinalText(text)
        updateSize()
    }

    func setMode(_ isContinue: Bool) {
        overlayViewModel.isContinueMode = isContinue
    }

    func updateTimer(_ seconds: Int) {
        overlayViewModel.timerSeconds = seconds
    }

    func setVocabularyName(_ name: String) {
        overlayViewModel.vocabularyName = name
    }

    func setPreviewedVocabularyName(_ name: String?, isPendingSwitch: Bool) {
        overlayViewModel.previewedVocabularyName = name
        overlayViewModel.isPendingSwitch = isPendingSwitch
    }

    func setConnecting(_ connecting: Bool) {
        overlayViewModel.isConnecting = connecting
    }

    func setReconnecting(_ reconnecting: Bool) {
        overlayViewModel.isReconnecting = reconnecting
    }

    func appendPastedText(_ text: String) {
        overlayViewModel.appendPastedText(text)
        updateSize()
    }

    @discardableResult
    func undoLastPaste() -> String? {
        let removed = overlayViewModel.undoLastPaste()
        updateSize()
        return removed
    }

    var isInterimEmpty: Bool {
        overlayViewModel.interimText.isEmpty
    }

    func triggerInterimBlocked() {
        overlayViewModel.isInterimBlocked = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            overlayViewModel.isInterimBlocked = false
            try? await Task.sleep(for: .milliseconds(150))
            overlayViewModel.isInterimBlocked = true
            try? await Task.sleep(for: .milliseconds(150))
            overlayViewModel.isInterimBlocked = false
            try? await Task.sleep(for: .milliseconds(150))
            overlayViewModel.isInterimBlocked = true
        }
    }

    func deleteLastWord() -> String? {
        let removed = overlayViewModel.deleteLastWord()
        updateSize()
        return removed
    }

    @discardableResult
    func deleteLastChar() -> Bool {
        let removed = overlayViewModel.deleteLastChar()
        updateSize()
        return removed
    }

    @discardableResult
    func appendSpace() -> Bool {
        let added = overlayViewModel.appendSpace()
        updateSize()
        return added
    }

    var overlayFinalText: String {
        overlayViewModel.finalText
    }

    func showFinalAndDismiss() {
        overlayViewModel.interimText = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.dismissAnimated()
        }
    }

    func showError(_ message: String) {
        overlayViewModel.reset()
        overlayViewModel.errorMessage = message
        overlayViewModel.isConnecting = false

        positionOnScreen(of: nil)
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.animator().alphaValue = 1
        }

        // Auto-dismiss after 2 seconds
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            self.dismissAnimated()
        }
    }

    func dismissImmediately() {
        orderOut(nil)
        alphaValue = 0
        overlayViewModel.reset()
    }

    // MARK: - Private

    private func dismissAnimated() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            self.animator().alphaValue = 0
        }) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.orderOut(nil)
                self.overlayViewModel.reset()
            }
        }
    }

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
        screenOriginY = y
        setFrame(NSRect(x: x, y: y, width: width, height: height), display: false)
    }

    /// Find the NSScreen that contains the front window of the given app
    /// using CGWindowList (does not require Accessibility permissions).
    private func screenForApp(_ app: NSRunningApplication?) -> NSScreen? {
        guard let app else { return nil }
        let pid = app.processIdentifier

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[CFString: Any]] else {
            return nil
        }

        // Find the first on-screen window belonging to the target app
        for entry in windowList {
            guard let ownerPID = entry[kCGWindowOwnerPID] as? Int32,
                  ownerPID == pid,
                  let bounds = entry[kCGWindowBounds] else {
                continue
            }

            var quartzRect = CGRect.zero
            // swiftlint:disable:next force_cast
            let boundsDict = bounds as! CFDictionary
            guard CGRectMakeWithDictionaryRepresentation(boundsDict, &quartzRect) else {
                continue
            }

            // Quartz uses top-left origin; convert center to Cocoa (bottom-left origin)
            guard let primaryScreen = NSScreen.screens.first else { return nil }
            let centerX = quartzRect.midX
            let centerY = primaryScreen.frame.height - quartzRect.midY
            let cocoaCenter = NSPoint(x: centerX, y: centerY)

            if let screen = NSScreen.screens.first(where: { $0.frame.contains(cocoaCenter) }) {
                return screen
            }
        }

        return nil
    }

    private func updateSize() {
        DispatchQueue.main.async { [self] in
            let fittingSize = hostingView.fittingSize
            let width: CGFloat = 400
            let height = max(fittingSize.height, 60)
            setFrame(NSRect(x: frame.origin.x, y: screenOriginY, width: width, height: height), display: true)
        }
    }
}

// MARK: - Overlay ViewModel

enum TextSegmentType {
    case dictated
    case pasted
}

struct TextSegment: Identifiable {
    let id = UUID()
    var text: String
    let type: TextSegmentType
}

@MainActor
final class OverlayViewModel: ObservableObject {
    @Published var finalSegments: [TextSegment] = []

    var finalText: String {
        finalSegments.map(\.text).joined()
    }
    @Published var interimText = ""
    @Published var isContinueMode = false
    @Published var timerSeconds = 0
    @Published var vocabularyName = ""
    @Published var previewedVocabularyName: String?
    @Published var isPendingSwitch = false
    @Published var isReconnecting = false
    @Published var isConnecting = true
    @Published var isInterimBlocked = false
    @Published var maxTextHeight: CGFloat = 250
    @Published var removingSegmentId: UUID?
    @Published var errorMessage: String?

    var displayedVocabularyName: String {
        previewedVocabularyName ?? vocabularyName
    }

    var showReturnSymbol: Bool {
        isPendingSwitch
    }

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

    func appendPastedText(_ text: String) {
        guard !text.isEmpty else { return }
        let needsSpace = !finalSegments.isEmpty && !(finalSegments.last?.text.hasSuffix(" ") ?? true)
        let padded = (needsSpace ? " " : "") + text + (text.hasSuffix(" ") ? "" : " ")
        finalSegments.append(TextSegment(text: padded, type: .pasted))
    }

    /// Removes the last pasted segment. Returns the removed text or nil.
    @discardableResult
    func undoLastPaste() -> String? {
        guard let lastPasteIndex = finalSegments.lastIndex(where: { $0.type == .pasted }) else {
            return nil
        }
        let removed = finalSegments.remove(at: lastPasteIndex)
        return removed.text
    }

    /// Removes the last word from the last segment. Returns the removed word or nil.
    func deleteLastWord() -> String? {
        guard !finalSegments.isEmpty else { return nil }
        let lastSegment = finalSegments[finalSegments.count - 1]
        let trimmed = lastSegment.text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            finalSegments.removeLast()
            return deleteLastWord()
        }

        let words = trimmed.components(separatedBy: " ")
        guard let lastWord = words.last, !lastWord.isEmpty else { return nil }

        if words.count <= 1 {
            // Entire segment is one word — remove the segment
            finalSegments.removeLast()
            return lastWord
        } else {
            // Remove last word, keep trailing space
            let newText = words.dropLast().joined(separator: " ") + " "
            finalSegments[finalSegments.count - 1] = TextSegment(text: newText, type: lastSegment.type)
            return lastWord
        }
    }

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

    /// Appends a space to the last segment (or creates one). Returns false if already ends with space.
    @discardableResult
    func appendSpace() -> Bool {
        if finalSegments.isEmpty {
            finalSegments.append(TextSegment(text: " ", type: .dictated))
            return true
        }
        let lastSegment = finalSegments[finalSegments.count - 1]
        guard !lastSegment.text.hasSuffix(" ") else { return false }

        finalSegments[finalSegments.count - 1] = TextSegment(
            text: lastSegment.text + " ",
            type: lastSegment.type
        )
        return true
    }

    func reset() {
        finalSegments = []
        interimText = ""
        isContinueMode = false
        timerSeconds = 0
        vocabularyName = ""
        previewedVocabularyName = nil
        isPendingSwitch = false
        isReconnecting = false
        isConnecting = true
        isInterimBlocked = false
        removingSegmentId = nil
        errorMessage = nil
    }

    var displayText: String {
        let final = finalText
        if !interimText.isEmpty {
            if final.isEmpty {
                return interimText
            }
            return final + " " + interimText
        }
        return final
    }
}

// MARK: - Overlay SwiftUI View

struct OverlayContentView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @State private var blinkOpacity: Double = 1.0

    @State private var dotPulse = false

    var body: some View {
        if let error = viewModel.errorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(error)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(red: 1.0, green: 0.7, blue: 0.7))
            }
            .padding()
            .frame(width: 400)
            .background(
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl))
        } else {
            VStack(alignment: .leading, spacing: 4) {
                // Header: status dot + mode indicator + vocabulary name + return symbol + timer
                HStack(spacing: 6) {
                    // Connection status dot
                    Circle()
                        .fill(viewModel.isConnecting ? Color.yellow : Color.green)
                        .frame(width: 8, height: 8)
                        .opacity(dotPulse ? (viewModel.isConnecting ? 0.3 : 1.0) : 1.0)
                        .onChange(of: viewModel.isConnecting) { _, connecting in
                            if connecting {
                                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                                    dotPulse = true
                                }
                            } else {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    dotPulse = false
                                }
                            }
                        }
                        .onAppear {
                            if viewModel.isConnecting {
                                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                                    dotPulse = true
                                }
                            }
                        }

                    Text(viewModel.isContinueMode ? "a" : "A")
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                        .foregroundStyle(viewModel.isContinueMode ? .orange : DS.Colors.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            (viewModel.isContinueMode ? Color.orange : DS.Colors.primary).opacity(0.15)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))

                    if !viewModel.displayedVocabularyName.isEmpty {
                        Text(viewModel.displayedVocabularyName)
                            .font(DS.Typography.monoCaption)
                            .foregroundStyle(.primary)
                            .opacity(blinkOpacity)
                            .onChange(of: viewModel.isReconnecting) { _, reconnecting in
                                if reconnecting {
                                    withAnimation(DS.blink) { blinkOpacity = 0.3 }
                                } else {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        blinkOpacity = 1.0
                                    }
                                }
                            }
                    }

                    if viewModel.showReturnSymbol {
                        Text("\u{23CE}")
                            .font(DS.Typography.monoCaption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(formatTime(viewModel.timerSeconds))
                        .font(DS.Typography.monoCaption)
                        .foregroundStyle(.secondary)
                }

                // Transcription text
                segmentedText()
            }
            .padding(DS.Spacing.md)
            .frame(width: 400)
            .background(
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl))
        }
    }

    @ViewBuilder
    private func segmentedText() -> some View {
        if viewModel.finalSegments.isEmpty && viewModel.interimText.isEmpty {
            Text("Listening...")
                .font(DS.Typography.caption)
                .italic()
                .foregroundStyle(.secondary.opacity(0.5))
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    buildTextView()
                        .font(DS.Typography.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("bottom")
                }
                .onChange(of: viewModel.displayText) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .frame(maxHeight: viewModel.maxTextHeight)
        }
    }

    private func buildTextView() -> Text {
        var result = Text("")

        for segment in viewModel.finalSegments {
            let color: Color = switch segment.type {
            case .dictated: DS.Colors.overlayFinalized
            case .pasted: DS.Colors.overlayPasted
            }
            result = result + Text(segment.text).foregroundColor(color)
        }

        if !viewModel.interimText.isEmpty {
            let spacer = viewModel.finalSegments.isEmpty ? "" : " "
            let interimColor: Color = viewModel.isInterimBlocked
                ? DS.Colors.overlayInterimBlocked
                : DS.Colors.overlayInterim
            result = result + Text(spacer + viewModel.interimText)
                .foregroundColor(interimColor)
        }

        return result
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Visual Effect

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
