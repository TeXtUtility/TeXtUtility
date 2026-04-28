import Foundation

/// Per-word complexity score derived from four orthogonal factors. Real typists slow
/// down on hard words; the slowdown shows up as both a longer onset pause (planning /
/// lookahead before the first letter) and elevated within-word IKI for hard bigrams.
///
/// Research grounding:
///   - Salthouse 1986: typists are systematically slower on infrequent letters and
///     unfamiliar bigrams.
///   - Inhoff & Gordon 1997: word-frequency effects on typing latency are real and
///     measurable (~50–150 ms onset difference between common and rare words).
///   - Crump & Logan 2010: hierarchical control — there's a planning step before
///     each word that scales with complexity (visible as an onset pause).
///   - Dhakal et al. CHI 2018: per-bigram timing varies by 0.85×–1.40× of mean.
///
/// Output is a unitless score; ~1.0 = average, <1.0 = easy, >1.0 = hard. Range
/// realistically [0.80, 1.60]. The Planner maps this to onset-pause-ms and
/// within-word slowdown multiplier.
enum WordComplexity {
    static func score(for word: String) -> Double {
        guard !word.isEmpty else { return 1.0 }
        let lower = word.lowercased()

        // 1. Average bigram cost across the word — captures awkward finger sequences.
        var bigramSum = 0.0
        var bigramCount = 0
        var prev: Character? = nil
        for c in lower where c.isLetter {
            if let p = prev {
                bigramSum += BigramTable.multiplier(prev: p, current: c, strength: 1.0)
                bigramCount += 1
            }
            prev = c
        }
        let avgBigram = bigramCount > 0 ? bigramSum / Double(bigramCount) : 1.0

        // 2. Word-frequency factor. Common words are typed ~12% faster (Inhoff & Gordon).
        let freqFactor: Double = {
            switch CommonWords.classify(lower) {
            case .common:       return 0.88
            case .neutral:      return 1.00
            case .longUncommon: return 1.12
            }
        }()

        // 3. Length factor — only long words pay an extra penalty (planning load).
        // Words ≤ 6 chars get no length penalty.
        let lengthFactor = 1.0 + max(0, Double(lower.count) - 6.0) * 0.015

        // 4. Rare-letter penalty. q/x/z/j force less-practiced finger motions.
        let rareCount = lower.filter { "qxzj".contains($0) }.count
        let rarityFactor = 1.0 + Double(rareCount) * 0.05

        return avgBigram * freqFactor * lengthFactor * rarityFactor
    }

    /// How much to slow per-keystroke IKI for this word's letters. Caps at +25%.
    static func withinWordSlowdown(complexity: Double) -> Double {
        return 1.0 + max(0, complexity - 1.0) * 0.50
    }

    /// Extra pause before the word's first character — the spelling-planning beat.
    /// Rough range: 0 ms for easy words, up to ~360 ms for the hardest words.
    static func onsetPauseMs(complexity: Double) -> Double {
        return max(0, complexity - 1.0) * 600
    }
}
