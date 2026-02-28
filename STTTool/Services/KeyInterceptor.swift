import CoreGraphics
import Foundation

/// Intercepts keyboard events at the system level via CGEventTap.
/// Unlike NSEvent global monitors, CGEventTap can consume events
/// (return nil) so they don't reach the active application.
final class KeyInterceptor: @unchecked Sendable {
    static let shared = KeyInterceptor()

    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private struct KeyCombo: Hashable {
        let keyCode: UInt16
        let modifiers: CGEventFlags

        // Only compare relevant modifier bits
        static let relevantFlags: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]

        func matches(keyCode: UInt16, flags: CGEventFlags) -> Bool {
            self.keyCode == keyCode && self.modifiers == flags.intersection(KeyCombo.relevantFlags)
        }

        // CGEventFlags doesn't conform to Hashable, so implement manually via rawValue
        static func == (lhs: KeyCombo, rhs: KeyCombo) -> Bool {
            lhs.keyCode == rhs.keyCode && lhs.modifiers.rawValue == rhs.modifiers.rawValue
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(keyCode)
            hasher.combine(modifiers.rawValue)
        }
    }

    private var handlers: [KeyCombo: () -> Void] = [:]
    private let lock = NSLock()

    private init() {}

    /// Create and enable the event tap. Call once at app startup.
    func start() {
        guard eventTap == nil else { return }

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: keyInterceptorCallback,
            userInfo: userInfo
        ) else {
            print("[KeyInterceptor] Failed to create event tap — check Accessibility permissions")
            return
        }

        eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("[KeyInterceptor] Event tap started")
    }

    /// Register a handler for a specific keyCode with optional modifier keys.
    /// The key event will be consumed when matched.
    func intercept(keyCode: UInt16, modifiers: CGEventFlags = [], handler: @escaping () -> Void) {
        let combo = KeyCombo(keyCode: keyCode, modifiers: modifiers.intersection(KeyCombo.relevantFlags))
        lock.lock()
        handlers[combo] = handler
        lock.unlock()
        ensureTapEnabled()
    }

    /// Remove the handler for a specific keyCode.
    func stopIntercepting(keyCode: UInt16, modifiers: CGEventFlags = []) {
        let combo = KeyCombo(keyCode: keyCode, modifiers: modifiers.intersection(KeyCombo.relevantFlags))
        lock.lock()
        handlers.removeValue(forKey: combo)
        lock.unlock()
    }

    /// Remove all handlers.
    func stopAll() {
        lock.lock()
        handlers.removeAll()
        lock.unlock()
    }

    // MARK: - Internal

    /// Called from the C callback on the main thread.
    fileprivate func handleKeyEvent(_ keyCode: UInt16, flags: CGEventFlags) -> Bool {
        lock.lock()
        let matchedHandler = handlers.first { $0.key.matches(keyCode: keyCode, flags: flags) }?.value
        lock.unlock()

        if let handler = matchedHandler {
            DispatchQueue.main.async { handler() }
            return true // consumed
        }
        return false // pass through
    }

    private func ensureTapEnabled() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
}

// MARK: - C Callback

private func keyInterceptorCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // Re-enable tap if macOS disabled it due to timeout
    if type == .tapDisabledByTimeout {
        if let userInfo {
            let interceptor = Unmanaged<KeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
            if let tap = interceptor.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return Unmanaged.passUnretained(event)
    }

    guard type == .keyDown, let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags
    let interceptor = Unmanaged<KeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()

    if interceptor.handleKeyEvent(keyCode, flags: flags) {
        return nil // consume event
    }

    return Unmanaged.passUnretained(event)
}
