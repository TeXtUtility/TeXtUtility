import CoreGraphics

/// Special-purpose keycodes used outside the per-character KeycodeMap (navigation,
/// editing). These are the macOS virtual keycodes; Mac apps including Google Docs
/// in Chrome respond to them directly.
enum Keycodes {
    static let backspace: CGKeyCode = 51
    static let returnKey: CGKeyCode = 36
    static let tab: CGKeyCode = 48
    static let escape: CGKeyCode = 53
    static let space: CGKeyCode = 49

    static let leftArrow: CGKeyCode = 123
    static let rightArrow: CGKeyCode = 124
    static let downArrow: CGKeyCode = 125
    static let upArrow: CGKeyCode = 126

    static let home: CGKeyCode = 115
    static let end: CGKeyCode = 119
}
