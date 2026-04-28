import CoreGraphics

enum ModifierGuard {
    private static let allModifierKeys: [CGKeyCode] = [
        54, // command right
        55, // command left
        56, // shift left
        57, // capslock
        58, // option left
        59, // control left
        60, // shift right
        61, // option right
        62, // control right
        63, // fn
    ]

    /// Belt-and-braces: emit key-up CGEvents for every modifier, regardless of whether
    /// we sent the corresponding key-down. Called on completion, abort, and any thrown
    /// error path to prevent stuck modifiers — the #1 user-visible failure mode.
    static func flushAllModifiers(source: CGEventSource?, location: CGEventTapLocation) {
        for code in allModifierKeys {
            guard let ev = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { continue }
            ev.flags = []
            ev.post(tap: location)
        }
    }
}
