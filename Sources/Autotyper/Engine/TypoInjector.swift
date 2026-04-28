import Foundation

/// Convert raw text into a [LogicalKey] stream, splicing in typos with realistic
/// recognition and correction. Word-frequency-aware: common words ("the", "and")
/// fumble more often but are caught instantly; long uncommon words get fewer typos
/// but slower recognition when they do happen.
///
/// Distribution from research brief:
///   60% insertion, 20% substitution, 15% omission, 5% transposition.
///
/// Each error has a recognition delay (lognormal mean 250 ms, scaled by word
/// frequency class) before the rapid backspace burst.
enum TypoInjector {
    struct Params {
        var baseErrorRate: Double      // per-letter probability before frequency multiplier
        var recognitionMeanMs: Double  // base recognition delay before backspacing
        var recognitionSigma: Double
        var allowOnFirstChar: Bool

        static let defaults = Params(
            baseErrorRate: 0.03,
            recognitionMeanMs: 250,
            recognitionSigma: 0.5,
            allowOnFirstChar: false
        )
    }

    /// Pre-extract word boundaries from text so we can classify each char's word.
    /// Returns an array indexed by char position; each entry is the lowercased word
    /// containing that char, or nil for non-letters.
    private static func wordContext(for text: [Character]) -> [String?] {
        var result: [String?] = Array(repeating: nil, count: text.count)
        var i = 0
        while i < text.count {
            if text[i].isLetter {
                var j = i
                while j < text.count && text[j].isLetter { j += 1 }
                let word = String(text[i..<j]).lowercased()
                for k in i..<j { result[k] = word }
                i = j
            } else {
                i += 1
            }
        }
        return result
    }

    /// Process a sequence of TextScripts. `.run` blocks get full typo injection;
    /// `.dwell` blocks are emitted as type-pause-backspace-retype with no nested
    /// errors (the dwell motion is itself a deliberate error/correction; layering
    /// typos on top would over-noise it).
    ///
    /// `fatigue` (if non-nil and the session clears the length threshold) ramps
    /// the per-character error rate up across the final fraction of the source
    /// text, modeling end-of-session attention drift in long-form drafting.
    static func toLogicalKeys(
        scripts: [TextScript],
        params: Params,
        fatigue: FatigueParams? = nil,
        thinkingPauseMs: Double = 900,
        realizationPauseMs: Double = 450,
        sampler: Sampler
    ) -> [LogicalKey] {
        let totalChars = scripts.reduce(0) { acc, s in
            switch s {
            case .run(let t): return acc + t.count
            case .dwell(_, let then): return acc + then.count
            }
        }
        let fatigueIntensity = fatigue.map {
            FatigueModel.intensity(totalChars: totalChars, params: $0)
        } ?? 0

        var out: [LogicalKey] = []
        var globalPos = 0
        for script in scripts {
            switch script {
            case .run(let text):
                injectInto(
                    text: text,
                    params: params,
                    fatigue: fatigue,
                    fatigueIntensity: fatigueIntensity,
                    globalStartPos: globalPos,
                    totalChars: totalChars,
                    sampler: sampler,
                    out: &out
                )
                globalPos += text.count
            case .dwell(let typed, let then):
                emitDwell(typed: typed, then: then,
                          thinkingPauseMs: thinkingPauseMs,
                          realizationPauseMs: realizationPauseMs,
                          sampler: sampler,
                          out: &out)
                globalPos += then.count
            }
        }
        return out
    }

    /// Direct-from-text path; kept for tests / fallback.
    static func toLogicalKeys(
        text: String,
        params: Params,
        sampler: Sampler
    ) -> [LogicalKey] {
        var out: [LogicalKey] = []
        injectInto(
            text: text, params: params,
            fatigue: nil, fatigueIntensity: 0,
            globalStartPos: 0, totalChars: text.count,
            sampler: sampler, out: &out
        )
        return out
    }

    private static func injectInto(
        text: String,
        params: Params,
        fatigue: FatigueParams?,
        fatigueIntensity: Double,
        globalStartPos: Int,
        totalChars: Int,
        sampler: Sampler,
        out: inout [LogicalKey]
    ) {
        let chars = Array(text)
        let words = wordContext(for: chars)

        var i = 0
        while i < chars.count {
            let c = chars[i]

            let canInject = c.isLetter
                && (params.allowOnFirstChar || i > 0 || !out.isEmpty)
                && QwertyAdjacency.adjacent(of: c, sampler: sampler) != nil

            let cls: CommonWords.Class = words[i].map(CommonWords.classify) ?? .neutral
            var rate = params.baseErrorRate * CommonWords.errorRateMultiplier(for: cls)
            if let f = fatigue, fatigueIntensity > 0, totalChars > 0 {
                let progress = Double(globalStartPos + i) / Double(totalChars)
                rate *= FatigueModel.multiplier(
                    progress: progress,
                    intensity: fatigueIntensity,
                    params: f,
                    endValue: f.errorMultiplierAtEnd
                )
            }

            if canInject && sampler.bool(probability: rate) {
                let consumed = injectError(
                    at: i,
                    chars: chars,
                    cls: cls,
                    params: params,
                    sampler: sampler,
                    out: &out
                )
                i += consumed
                continue
            }

            out.append(.char(c))
            i += 1
        }
    }

    private static func emitDwell(
        typed: String,
        then: String,
        thinkingPauseMs: Double,
        realizationPauseMs: Double,
        sampler: Sampler,
        out: inout [LogicalKey]
    ) {
        let thinking = sampler.lognormalClamped(mean: thinkingPauseMs, sigma: 0.4, lower: 400, upper: 3500)
        let realization = sampler.lognormalClamped(mean: realizationPauseMs, sigma: 0.3, lower: 150, upper: 1500)

        out.append(.extraDelayMs(thinking))
        for ch in typed { out.append(.char(ch)) }
        out.append(.extraDelayMs(realization))
        for _ in 0..<typed.count { out.append(.backspace) }
        for ch in then { out.append(.char(ch)) }
    }

    /// Splice an error sequence at position i. Returns the number of source chars
    /// consumed (always ≥ 1). The output stream advances by one error
    /// (initial-wrong-typing + recognition + backspace + retype).
    private static func injectError(
        at i: Int,
        chars: [Character],
        cls: CommonWords.Class,
        params: Params,
        sampler: Sampler,
        out: inout [LogicalKey]
    ) -> Int {
        let r = sampler.uniform()
        let recognitionMean = params.recognitionMeanMs * CommonWords.recognitionMultiplier(for: cls)
        let recognitionDelay = sampler.lognormalClamped(
            mean: recognitionMean,
            sigma: params.recognitionSigma,
            lower: 80,
            upper: 1500
        )

        if r < 0.60 {
            return injectInsertion(at: i, chars: chars, recognitionMs: recognitionDelay, sampler: sampler, out: &out)
        } else if r < 0.80 {
            return injectSubstitution(at: i, chars: chars, recognitionMs: recognitionDelay, sampler: sampler, out: &out)
        } else if r < 0.95 {
            return injectOmission(at: i, chars: chars, recognitionMs: recognitionDelay, sampler: sampler, out: &out)
        } else {
            return injectTransposition(at: i, chars: chars, recognitionMs: recognitionDelay, sampler: sampler, out: &out)
        }
    }

    // MARK: - Error type implementations
    //
    // Each returns the number of *source* characters consumed. Each emits the wrong
    // typing forward, an extraDelayMs (recognition), backspaces, and the correct
    // retyping.

    private static func injectInsertion(
        at i: Int,
        chars: [Character],
        recognitionMs: Double,
        sampler: Sampler,
        out: inout [LogicalKey]
    ) -> Int {
        // Type adjacent-key wrongChar BEFORE c[i]; continue 1..4 chars normally before noticing.
        guard let wrong = QwertyAdjacency.adjacent(of: chars[i], sampler: sampler) else {
            out.append(.char(chars[i])); return 1
        }
        let extraK = Int(sampler.uniform(in: 0...4))
        let consumed = min(1 + extraK, chars.count - i)

        out.append(.char(wrong))
        for k in 0..<consumed { out.append(.char(chars[i + k])) }
        out.append(.extraDelayMs(recognitionMs))
        // We typed (1 + consumed) chars; backspace all of them.
        for _ in 0..<(1 + consumed) { out.append(.backspace) }
        // Retype c[i..i+consumed] correctly.
        for k in 0..<consumed { out.append(.char(chars[i + k])) }
        return consumed
    }

    private static func injectSubstitution(
        at i: Int,
        chars: [Character],
        recognitionMs: Double,
        sampler: Sampler,
        out: inout [LogicalKey]
    ) -> Int {
        guard let wrong = QwertyAdjacency.adjacent(of: chars[i], sampler: sampler) else {
            out.append(.char(chars[i])); return 1
        }
        let extraK = Int(sampler.uniform(in: 0...2))
        let consumed = min(1 + extraK, chars.count - i)

        // Type wrong instead of c[i], then c[i+1..i+consumed].
        out.append(.char(wrong))
        for k in 1..<consumed { out.append(.char(chars[i + k])) }
        out.append(.extraDelayMs(recognitionMs))
        for _ in 0..<consumed { out.append(.backspace) }
        for k in 0..<consumed { out.append(.char(chars[i + k])) }
        return consumed
    }

    private static func injectOmission(
        at i: Int,
        chars: [Character],
        recognitionMs: Double,
        sampler: Sampler,
        out: inout [LogicalKey]
    ) -> Int {
        // Skip c[i], continue 1..3 chars; then notice and retype.
        let extraK = Int(sampler.uniform(in: 1...3))
        let lookahead = min(extraK, chars.count - i - 1)
        if lookahead < 1 {
            // Near end of string; degrade to substitution to avoid no-op.
            return injectSubstitution(at: i, chars: chars, recognitionMs: recognitionMs, sampler: sampler, out: &out)
        }
        // Type c[i+1..i+1+lookahead] (the omission means c[i] never got typed).
        for k in 1...lookahead { out.append(.char(chars[i + k])) }
        out.append(.extraDelayMs(recognitionMs))
        // Backspace `lookahead` chars (we typed them after the omitted one).
        for _ in 0..<lookahead { out.append(.backspace) }
        // Retype c[i..i+lookahead].
        for k in 0...lookahead { out.append(.char(chars[i + k])) }
        return lookahead + 1
    }

    private static func injectTransposition(
        at i: Int,
        chars: [Character],
        recognitionMs: Double,
        sampler: Sampler,
        out: inout [LogicalKey]
    ) -> Int {
        guard i + 1 < chars.count, chars[i + 1].isLetter else {
            return injectSubstitution(at: i, chars: chars, recognitionMs: recognitionMs, sampler: sampler, out: &out)
        }
        let extraK = Int(sampler.uniform(in: 0...2))
        let lookahead = min(extraK, chars.count - i - 2)

        // Type c[i+1] then c[i] (transposition), then c[i+2..i+2+lookahead] correctly.
        out.append(.char(chars[i + 1]))
        out.append(.char(chars[i]))
        for k in 0..<lookahead { out.append(.char(chars[i + 2 + k])) }
        out.append(.extraDelayMs(recognitionMs))
        let typedCount = 2 + lookahead
        for _ in 0..<typedCount { out.append(.backspace) }
        for k in 0..<typedCount { out.append(.char(chars[i + k])) }
        return typedCount
    }
}
