import Foundation

/// Hanzi → ASCII pinyin transliteration so source text containing Chinese
/// characters can be retyped through the target app's pinyin IME. Each
/// hanzi is expanded to its base-letters Mandarin pinyin (no tone marks)
/// followed by a space, which is the gesture most pinyin IMEs use to
/// commit the first candidate. CJK punctuation is converted to its ASCII
/// equivalent (the IME generally maps that back to its Chinese form when
/// in Chinese input mode). ASCII and other characters pass through
/// unchanged so mixed-language text ("Hello 你好") survives.
///
/// The transliteration uses the standard ICU MandarinLatin transform via
/// `CFStringTransform`, which ships with macOS — no external pinyin
/// dictionary is bundled. The transform picks one reading per character;
/// polyphones (行 = xíng / háng, 重 = zhòng / chóng) get the most-common
/// reading, and the user's IME may produce a different character than
/// intended in those edge cases. Most common hanzi are unambiguous.
enum PinyinTransliterator {
    /// True if `text` contains any CJK ideograph that should trigger the
    /// pinyin path. Covers CJK Unified, Extension A, Compatibility
    /// Ideographs, and Extensions B–F (supplementary plane).
    static func containsHanzi(_ text: String) -> Bool {
        for ch in text {
            for scalar in ch.unicodeScalars where isHanzi(scalar) {
                return true
            }
        }
        return false
    }

    /// Expand source text into ASCII suitable for pinyin-IME input.
    /// Hanzi → pinyin + space. CJK punctuation → ASCII equivalent (no
    /// trailing space). ASCII and all other characters pass through.
    ///
    ///   "我喜欢学习中文。"   → "wo xi huan xue xi zhong wen ."
    ///   "Hello 你好, 世界!"  → "Hello ni hao , shi jie !"
    static func expandToPinyinAscii(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count * 3)
        for ch in text {
            guard let scalar = ch.unicodeScalars.first else {
                out.append(ch)
                continue
            }
            if isHanzi(scalar) {
                if let py = transliterate(ch) {
                    out.append(py)
                    out.append(" ")
                }
                // If transliteration somehow fails, drop the char — emitting
                // an unmappable hanzi the executor would silently skip is
                // worse than just leaving it out of the typed stream.
                continue
            }
            if isCjkPunctuation(scalar) {
                if let ascii = transliterate(ch) {
                    out.append(ascii)
                } else {
                    out.append(ch)
                }
                continue
            }
            out.append(ch)
        }
        return out
    }

    // MARK: - Internals

    private static func isHanzi(_ s: Unicode.Scalar) -> Bool {
        let v = s.value
        return (0x4E00...0x9FFF).contains(v) ||   // CJK Unified Ideographs
               (0x3400...0x4DBF).contains(v) ||   // CJK Extension A
               (0xF900...0xFAFF).contains(v) ||   // CJK Compatibility Ideographs
               (0x20000...0x2FFFF).contains(v)    // CJK Extensions B–F
    }

    private static func isCjkPunctuation(_ s: Unicode.Scalar) -> Bool {
        let v = s.value
        return (0x3000...0x303F).contains(v) ||   // CJK Symbols and Punctuation
               (0xFF00...0xFFEF).contains(v)      // Halfwidth/Fullwidth Forms
    }

    private static func transliterate(_ ch: Character) -> String? {
        let s = NSMutableString(string: String(ch))
        guard CFStringTransform(s, nil, kCFStringTransformMandarinLatin, false) else {
            return nil
        }
        let stripped = (s as String).folding(
            options: .diacriticInsensitive,
            locale: Locale(identifier: "en")
        )
        let trimmed = stripped.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
