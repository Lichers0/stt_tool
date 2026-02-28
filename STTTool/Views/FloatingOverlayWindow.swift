import AppKit
import SwiftUI

final class FloatingOverlayWindow: NSPanel {

    private let hostingView: NSHostingView<OverlayContentView>
    private let overlayViewModel = OverlayViewModel()

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

    /// Final transcript text with correct segment ordering (including pastes).
    /// Mirrors DeepgramService.getResultText logic but uses overlay's ordered segments.
    var finalTranscriptText: String {
        let final = overlayViewModel.finalText
        let interim = overlayViewModel.interimText.trimmingCharacters(in: .whitespacesAndNewlines)
        if interim.isEmpty { return final }
        if final.isEmpty { return interim }
        if final.hasSuffix(interim) { return final }
        return final + " " + interim
    }

    func showFinalAndDismiss() {
        overlayViewModel.interimText = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.dismissAnimated()
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
        let x = visibleFrame.midX - frame.width / 2
        let y = visibleFrame.origin.y + 40
        setFrameOrigin(NSPoint(x: x, y: y))
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
        let fittingSize = hostingView.fittingSize
        let width: CGFloat = 400
        let height = min(max(fittingSize.height, 60), 300)
        setContentSize(NSSize(width: width, height: height))
    }
}

// MARK: - Overlay ViewModel

enum TextSegmentType {
    case dictated
    case pasted
}

struct TextSegment {
    let text: String
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

    var displayedVocabularyName: String {
        previewedVocabularyName ?? vocabularyName
    }

    var showReturnSymbol: Bool {
        isPendingSwitch
    }

    func appendFinalText(_ text: String) {
        // Insert before any trailing pasted segments so dictated text
        // appears before pastes that were added while it was still interim.
        var insertIndex = finalSegments.count
        while insertIndex > 0 && finalSegments[insertIndex - 1].type == .pasted {
            insertIndex -= 1
        }
        let needsSpace = insertIndex > 0 && !(finalSegments[insertIndex - 1].text.hasSuffix(" "))
        let paddedText = needsSpace ? " " + text : text
        finalSegments.insert(TextSegment(text: paddedText, type: .dictated), at: insertIndex)
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
            .frame(maxHeight: 250)
        }
    }

    private func buildTextView() -> Text {
        var result = Text("")

        for segment in viewModel.finalSegments {
            let color: Color = segment.type == .pasted
                ? .white.opacity(0.7)
                : .white
            result = result + Text(segment.text).foregroundColor(color)
        }

        if !viewModel.interimText.isEmpty {
            let spacer = viewModel.finalSegments.isEmpty ? "" : " "
            result = result + Text(spacer + viewModel.interimText).foregroundColor(.white)
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
