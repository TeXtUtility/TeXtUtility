import Foundation
import CoreGraphics

/// Intermediate representation between text and KeyEvents. The TypoInjector and the
/// SynonymDweller both produce a stream of LogicalKeys; the Planner walks that stream
/// and applies timing rules.
///
/// `.rawKey` carries arrow-key navigation, word-jump (Option+Arrow), Find
/// (⌘F), and similar modifier-key chords used by MidDraftReviser and
/// MistakeReviser. The planner treats these with arrow-speed IKI, slower than
/// typing.
///
/// `.fastArrow` is for held-key auto-repeat-style bursts of plain arrow keys
/// (no modifiers): used by MidDraftReviser when navigating back/forward by
/// many characters. Real users hold the arrow key for long-distance nav,
/// producing ~30 ms inter-press intervals — much faster than `.rawKey`'s
/// ~320 ms hand-speed.
enum LogicalKey {
    case char(Character)
    case backspace
    case rawKey(code: CGKeyCode, modifiers: CGEventFlags)
    case fastArrow(code: CGKeyCode)
    case extraDelayMs(Double)
}
