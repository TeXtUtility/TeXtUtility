import Foundation

/// QWERTY-aware bigram timing multipliers. The single highest-value feature for
/// defeating bot detection: real typists are systematically faster on hand-alternating
/// pairs ("th") than on same-finger awkward pairs ("ed", "ce"). Dhakal et al. CHI 2018
/// measured a ~46 ms gap between same-finger and hand-alternation bigrams.
///
/// Multipliers are applied to the base IKI; <1 is faster, >1 is slower.
enum Hand { case left, right, none }

enum BigramTable {
    /// Key → (hand, finger 0..3 with 0 = pinky, 3 = index, also includes thumbs as 4)
    private static let fingerMap: [Character: (Hand, Int, Int)] = {
        // (hand, finger, row). Row: 0 = number, 1 = top, 2 = home, 3 = bottom.
        var m: [Character: (Hand, Int, Int)] = [:]
        // Number row
        for (c, f) in zip("1234567890", [0,1,2,3,3,3,3,2,1,0]) { m[c] = (f < 4 ? .left : .right, f % 4, 0) }
        // Top row
        let top: [(Character, Hand, Int)] = [
            ("q", .left, 0), ("w", .left, 1), ("e", .left, 2), ("r", .left, 3), ("t", .left, 3),
            ("y", .right, 3), ("u", .right, 3), ("i", .right, 2), ("o", .right, 1), ("p", .right, 0)
        ]
        for (c, h, f) in top { m[c] = (h, f, 1) }
        // Home row
        let home: [(Character, Hand, Int)] = [
            ("a", .left, 0), ("s", .left, 1), ("d", .left, 2), ("f", .left, 3), ("g", .left, 3),
            ("h", .right, 3), ("j", .right, 3), ("k", .right, 2), ("l", .right, 1)
        ]
        for (c, h, f) in home { m[c] = (h, f, 2) }
        // Bottom row
        let bottom: [(Character, Hand, Int)] = [
            ("z", .left, 0), ("x", .left, 1), ("c", .left, 2), ("v", .left, 3), ("b", .left, 3),
            ("n", .right, 3), ("m", .right, 3)
        ]
        for (c, h, f) in bottom { m[c] = (h, f, 3) }
        return m
    }()

    /// Return the timing multiplier for typing c2 immediately after c1.
    /// Range roughly [0.85, 1.40]. 1.0 is baseline.
    /// `strength` compresses the range toward 1.0 (fast touch typists have practiced
    /// even awkward bigrams; strength 0.0 → all multipliers become 1.0).
    static func multiplier(prev: Character?, current: Character, strength: Double = 1.0) -> Double {
        let raw = rawMultiplier(prev: prev, current: current)
        return 1.0 + (raw - 1.0) * strength
    }

    private static func rawMultiplier(prev: Character?, current: Character) -> Double {
        guard let prevChar = prev else { return 1.0 }
        let p = Character(prevChar.lowercased())
        let c = Character(current.lowercased())
        // Letter repetition — preloaded finger, fast
        if p == c { return 0.85 }

        guard let (h1, f1, r1) = fingerMap[p], let (h2, f2, r2) = fingerMap[c] else {
            // One of the chars isn't a letter/digit — treat as neutral
            return 1.0
        }

        // Different hands → fast (hand alternation)
        if h1 != h2 { return 0.85 }

        // Same hand, same finger
        if f1 == f2 {
            let rowDist = abs(r1 - r2)
            if rowDist == 0 { return 1.05 }   // same key class but different (rare with our map)
            if rowDist == 1 { return 1.20 }   // same finger different row, e.g. "ed", "rf"
            return 1.30                        // cross-row same finger, e.g. "my", "ny"
        }

        // Same hand, adjacent fingers
        if abs(f1 - f2) == 1 { return 1.05 }

        // Same hand, non-adjacent fingers
        return 1.00
    }

    /// Boundary-pause classification keyed on the *current* character (the one about
    /// to be typed). Returned value is added to the IKI before this character.
    ///
    /// Sentence boundaries (after . ? !) guarantee 1000–2000 ms with a small heavy
    /// tail — that's the user-visible "thinking between sentences" pause.
    static func boundaryPauseMs(prev: Character?, current: Character, sampler: Sampler) -> Double {
        guard let prevChar = prev else { return 0 }
        switch prevChar {
        case ".", "?", "!":
            // Bulk of mass between 0.75–2.0 s; small 8% tail to 3.0 s.
            if sampler.bool(probability: 0.08) {
                return sampler.uniform(in: 2000.0...3000.0)
            }
            return sampler.uniform(in: 750.0...2000.0)
        case ",":
            return sampler.lognormalClamped(mean: 550, sigma: 0.4, lower: 250, upper: 1800)
        case ";", ":":
            return sampler.lognormalClamped(mean: 750, sigma: 0.4, lower: 350, upper: 2200)
        case " ":
            // Pre-quote / pre-paren — a reframe pause before opening punctuation.
            if current == "\"" || current == "'" || current == "(" || current == "[" {
                return sampler.lognormalClamped(mean: 450, sigma: 0.4, lower: 150, upper: 1500)
            }
            // Between-word boundary: typist just hit space, next char is the first
            // letter of a new word. Add a real pause here so the OT log shows
            // word-by-word op chunking. Without this, within-word speedup makes
            // average WPM too high; this restores realistic between-word gaps
            // (the 300-500 ms data from Inputlog corpora) and ensures Google's
            // OT chunker actually emits a new op for each new word.
            if current.isLetter || current.isNumber {
                return sampler.lognormalClamped(mean: 200, sigma: 0.45, lower: 80, upper: 750)
            }
            return 0
        case "\n":
            return sampler.lognormalClamped(mean: 900, sigma: 0.4, lower: 350, upper: 2500)
        default:
            return 0
        }
    }

    /// Heavy-tailed paragraph-break sampling. Called when we detect "\n\n" — emits
    /// either a soft, standard, or long break with weights from the plan.
    static func paragraphBreakMs(sampler: Sampler) -> Double {
        let r = sampler.uniform()
        if r < 0.25 {
            return sampler.lognormalClamped(mean: 2500, sigma: 0.4, lower: 800, upper: 5000)   // soft
        } else if r < 0.85 {
            return sampler.lognormalClamped(mean: 5000, sigma: 0.4, lower: 2000, upper: 9000)  // standard
        } else {
            return sampler.lognormalClamped(mean: 11000, sigma: 0.5, lower: 6000, upper: 22000) // long stretch break
        }
    }
}
