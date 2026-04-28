import ApplicationServices

enum AccessibilityCheck {
    static func isTrusted() -> Bool { AXIsProcessTrusted() }

    @discardableResult
    static func promptForAccess() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts: [String: Any] = [key: true]
        return AXIsProcessTrustedWithOptions(opts as CFDictionary)
    }
}
