import CoreGraphics
import Foundation

/// Intercepts keyboard events at the system level via CGEventTap.
/// Unlike NSEvent global monitors, CGEventTap can consume events
/// (return nil) so they don't reach the active application.
final class KeyInterceptor: @unchecked Sendable {
    static let shared = KeyInterceptor()

    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var handlers: [UInt16: () -> Void] = [:]
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

    /// Register a handler for a specific keyCode. The key event will be consumed.
    func intercept(keyCode: UInt16, handler: @escaping () -> Void) {
        lock.lock()
        handlers[keyCode] = handler
        lock.unlock()
        ensureTapEnabled()
    }

    /// Remove the handler for a specific keyCode.
    func stopIntercepting(keyCode: UInt16) {
        lock.lock()
        handlers.removeValue(forKey: keyCode)
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
    fileprivate func handleKeyEvent(_ keyCode: UInt16) -> Bool {
        lock.lock()
        let handler = handlers[keyCode]
        lock.unlock()

        if let handler {
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
    let interceptor = Unmanaged<KeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()

    if interceptor.handleKeyEvent(keyCode) {
        return nil // consume event
    }

    return Unmanaged.passUnretained(event)
}
