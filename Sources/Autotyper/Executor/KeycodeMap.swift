import CoreGraphics

enum KeycodeMap {
    /// Resolve an ASCII char to (virtualKey, shiftRequired). Returns nil for unmapped
    /// characters; Phase 6 adds a Unicode-string fallback for those.
    static func keycode(for char: Character) -> (code: CGKeyCode, shift: Bool)? {
        if char.isLetter, char.isASCII {
            let lower = Character(char.lowercased())
            guard let code = letterCodes[lower] else { return nil }
            return (code, char.isUppercase)
        }
        if let pair = symbolCodes[char] { return pair }
        if let code = digitCodes[char] { return (code, false) }
        return nil
    }

    static let shiftKey: CGKeyCode = 56

    private static let letterCodes: [Character: CGKeyCode] = [
        "a": 0,  "s": 1,  "d": 2,  "f": 3,  "h": 4,
        "g": 5,  "z": 6,  "x": 7,  "c": 8,  "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "o": 31, "u": 32, "i": 34,
        "p": 35, "l": 37, "j": 38, "k": 40, "n": 45,
        "m": 46,
    ]

    private static let digitCodes: [Character: CGKeyCode] = [
        "1": 18, "2": 19, "3": 20, "4": 21, "5": 23,
        "6": 22, "7": 26, "8": 28, "9": 25, "0": 29,
    ]

    private static let symbolCodes: [Character: (code: CGKeyCode, shift: Bool)] = [
        " ":  (49, false), "\n": (36, false), "\t": (48, false),
        "-":  (27, false), "_":  (27, true),
        "=":  (24, false), "+":  (24, true),
        "[":  (33, false), "{":  (33, true),
        "]":  (30, false), "}":  (30, true),
        "\\": (42, false), "|":  (42, true),
        ";":  (41, false), ":":  (41, true),
        "'":  (39, false), "\"": (39, true),
        ",":  (43, false), "<":  (43, true),
        ".":  (47, false), ">":  (47, true),
        "/":  (44, false), "?":  (44, true),
        "`":  (50, false), "~":  (50, true),
        "!":  (18, true),  "@":  (19, true),
        "#":  (20, true),  "$":  (21, true),
        "%":  (23, true),  "^":  (22, true),
        "&":  (26, true),  "*":  (28, true),
        "(":  (25, true),  ")":  (29, true),
    ]
}
