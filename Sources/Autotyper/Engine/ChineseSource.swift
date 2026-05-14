import Foundation

/// Detection and per-character classification for source text containing
/// hanzi (Chinese characters). When the source has any CJK ideograph, the
/// planner routes through a Chinese-aware path that inserts each
/// non-ASCII character directly via `CGEventKeyboardSetUnicodeString`
/// instead of trying to retype it. This is the only way to get
/// deterministic output for Chinese text: routing through a pinyin IME
/// produces ambiguity (the IME picks a candidate based on context and
/// user history, not always the source character), and racing keystrokes
/// against IME state produces dropped input.
///
/// Direct Unicode insertion lands the exact source character in any
/// modern macOS app — Safari, TextEdit, Notes, Pages, Notion, VS Code,
/// Google Docs in Chrome — regardless of input source or IME setup.
enum ChineseSource {
    /// True if `text` contains any CJK ideograph. Covers CJK Unified,
    /// Extension A, Compatibility Ideographs, and Extensions B–F.
    static func containsHanzi(_ text: String) -> Bool {
        for ch in text {
            for scalar in ch.unicodeScalars where isHanzi(scalar) {
                return true
            }
        }
        return false
    }

    /// True if the character should be inserted via Unicode rather than
    /// retyped through the keycode map. Catches every non-ASCII path that
    /// would otherwise be silently dropped: hanzi, CJK punctuation, full-
    /// width forms, accented letters, and similar.
    ///
    /// ASCII characters always pass through as `.char(c)` so the existing
    /// keycode-based path handles them. Newlines and tabs go through
    /// keycodes too so Return / Tab fire correctly.
    static func needsUnicodeInsertion(_ ch: Character) -> Bool {
        for scalar in ch.unicodeScalars {
            if scalar.value >= 0x80 { return true }
        }
        return false
    }

    private static func isHanzi(_ s: Unicode.Scalar) -> Bool {
        let v = s.value
        return (0x4E00...0x9FFF).contains(v) ||   // CJK Unified Ideographs
               (0x3400...0x4DBF).contains(v) ||   // CJK Extension A
               (0xF900...0xFAFF).contains(v) ||   // CJK Compatibility Ideographs
               (0x20000...0x2FFFF).contains(v)    // CJK Extensions B–F
    }
}
