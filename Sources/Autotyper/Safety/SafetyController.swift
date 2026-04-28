import AppKit
import CoreGraphics
import Foundation
import os

/// Global event-tap-based safety net. Runs continuously while the app is open.
///
/// Single guarantee: panic chord ⌥⌘. → abort within ≤50 ms, regardless of which
/// app is focused. The chord is swallowed so it doesn't propagate to the target.
///
/// User input and focus changes are intentionally NOT auto-aborted — events go
/// to the captured target PID via CGEventPostToPid, so the user can use other
/// apps freely without disrupting typing into the target.
final class SafetyController: @unchecked Sendable {
    static let shared = SafetyController()

    private let lock = OSAllocatedUnfairLock(initialState: State())
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private struct State {
        var isTypingActive: Bool = false
        var abortRequested: Bool = false
        var lastAbortReason: String?
        var onAbort: (@Sendable (String) -> Void)?
    }

    private init() {}

    // MARK: - Lifecycle

    /// Install the global event tap. Call once at app launch. Requires Accessibility
    /// permission; if not granted, returns false and the caller can show a banner.
    @discardableResult
    func installTap() -> Bool {
        if tap != nil { return true }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,  // can suppress events (needed for panic-chord swallow)
            eventsOfInterest: mask,
            callback: SafetyController.tapCallback,
            userInfo: refcon
        ) else {
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        self.tap = eventTap
        self.runLoopSource = source
        return true
    }

    // MARK: - Per-job state

    @MainActor
    func startTypingSession(onAbort: @escaping @Sendable (String) -> Void) {
        lock.withLock { s in
            s.isTypingActive = true
            s.abortRequested = false
            s.lastAbortReason = nil
            s.onAbort = onAbort
        }
        // Focus-change observer is intentionally NOT started here. Events are
        // delivered via CGEventPostToPid to the captured target PID, so the
        // user can switch focus to other apps and continue working without
        // disturbing typing into the original target.
    }

    func endTypingSession() {
        lock.withLock { s in
            s.isTypingActive = false
            s.onAbort = nil
        }
    }

    func requestAbort(reason: String) {
        let cb: (@Sendable (String) -> Void)? = lock.withLock { s in
            if !s.abortRequested {
                s.abortRequested = true
                s.lastAbortReason = reason
            }
            return s.onAbort
        }
        cb?(reason)
    }

    var isAbortRequested: Bool { lock.withLock { $0.abortRequested } }
    var lastAbortReason: String? { lock.withLock { $0.lastAbortReason } }

    // MARK: - Tap callback (runs on the main run-loop thread)

    private static let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let controller = Unmanaged<SafetyController>.fromOpaque(refcon).takeUnretainedValue()

        // Re-enable on system-disable events (taps can be disabled if the callback is
        // too slow or the user toggles Accessibility — defensive).
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = controller.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        // Panic chord: ⌥⌘. (period with Option+Command). Suppress the event so
        // the chord doesn't propagate to whatever app is focused. This is the
        // ONLY automatic abort path now — user input and focus changes no
        // longer abort, since we deliver events via CGEventPostToPid to the
        // target PID and let the user roam free.
        if type == .keyDown {
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags
            let hasCmd = flags.contains(.maskCommand)
            let hasOpt = flags.contains(.maskAlternate)
            // 47 = period
            if keycode == 47 && hasCmd && hasOpt {
                controller.requestAbort(reason: "Panic chord ⌥⌘.")
                return nil  // swallow
            }
        }

        return Unmanaged.passUnretained(event)
    }
}

