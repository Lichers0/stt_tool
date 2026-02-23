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

    func setReconnecting(_ reconnecting: Bool) {
        overlayViewModel.isReconnecting = reconnecting
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
        // Try to position below the text cursor of the target app
        if let app = targetApp, let cursorRect = getCursorPosition(for: app) {
            let x = cursorRect.origin.x
            let y = cursorRect.origin.y - frame.height - 8
            setFrameOrigin(NSPoint(x: x, y: max(y, 40)))
            return
        }

        // Fallback: bottom-center of the screen that contains the target app's window
        let screen = screenForApp(targetApp) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let visibleFrame = screen.visibleFrame
        let x = visibleFrame.midX - frame.width / 2
        let y = visibleFrame.origin.y + visibleFrame.height * 0.3
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func getCursorPosition(for app: NSRunningApplication) -> NSRect? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success else {
            return nil
        }

        var rangeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success else {
            return nil
        }

        var boundsValue: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            focusedElement as! AXUIElement,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue!,
            &boundsValue
        ) == .success else {
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect) else {
            return nil
        }

        // AX uses top-left origin; convert to Cocoa bottom-left origin using primary screen height
        guard let primaryScreen = NSScreen.screens.first else { return nil }
        let cocoaY = primaryScreen.frame.height - rect.origin.y - rect.height
        return NSRect(x: rect.origin.x, y: cocoaY, width: rect.width, height: rect.height)
    }

    /// Find the NSScreen that contains the front window of the given app.
    private func screenForApp(_ app: NSRunningApplication?) -> NSScreen? {
        guard let app else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Try focused window first, then fall back to main window
        var windowRef: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) != .success {
            AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &windowRef)
        }
        guard let windowRef else { return nil }

        var positionRef: AnyObject?
        guard AXUIElementCopyAttributeValue(windowRef as! AXUIElement, kAXPositionAttribute as CFString, &positionRef) == .success else {
            return nil
        }

        var position = CGPoint.zero
        guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &position) else {
            return nil
        }

        var sizeRef: AnyObject?
        guard AXUIElementCopyAttributeValue(windowRef as! AXUIElement, kAXSizeAttribute as CFString, &sizeRef) == .success else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else {
            return nil
        }

        // AX uses top-left origin; convert center point to Cocoa coordinates
        guard let primaryScreen = NSScreen.screens.first else { return nil }
        let centerX = position.x + size.width / 2
        let centerY = primaryScreen.frame.height - (position.y + size.height / 2)
        let cocoaCenter = NSPoint(x: centerX, y: centerY)

        // Find the screen that contains this point
        return NSScreen.screens.first { $0.frame.contains(cocoaCenter) }
    }

    private func updateSize() {
        let fittingSize = hostingView.fittingSize
        let width: CGFloat = 400
        let height = min(max(fittingSize.height, 60), 300)
        setContentSize(NSSize(width: width, height: height))
    }
}

// MARK: - Overlay ViewModel

@MainActor
final class OverlayViewModel: ObservableObject {
    @Published var finalText = ""
    @Published var interimText = ""
    @Published var isContinueMode = false
    @Published var timerSeconds = 0
    @Published var vocabularyName = ""
    @Published var previewedVocabularyName: String?
    @Published var isPendingSwitch = false
    @Published var isReconnecting = false

    var displayedVocabularyName: String {
        previewedVocabularyName ?? vocabularyName
    }

    var showReturnSymbol: Bool {
        isPendingSwitch
    }

    func appendFinalText(_ text: String) {
        if !finalText.isEmpty && !finalText.hasSuffix(" ") {
            finalText += " "
        }
        finalText += text
    }

    func reset() {
        finalText = ""
        interimText = ""
        isContinueMode = false
        timerSeconds = 0
        vocabularyName = ""
        previewedVocabularyName = nil
        isPendingSwitch = false
        isReconnecting = false
    }

    var displayText: String {
        if !interimText.isEmpty {
            if finalText.isEmpty {
                return interimText
            }
            return finalText + " " + interimText
        }
        return finalText
    }
}

// MARK: - Overlay SwiftUI View

struct OverlayContentView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @State private var blinkOpacity: Double = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header: mode indicator + vocabulary name + return symbol + timer
            HStack(spacing: 6) {
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
            if viewModel.displayText.isEmpty {
                Text("Listening...")
                    .font(DS.Typography.caption)
                    .italic()
                    .foregroundStyle(.secondary.opacity(0.5))
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        Text(viewModel.displayText)
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
        .padding(DS.Spacing.md)
        .frame(width: 400)
        .background(
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl))
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
