import Foundation
import CoreGraphics

/// Mid-draft cursor jumps. The single highest-value remaining anti-detection signal:
/// real student writing has 25–40% of insertions occurring at non-leading-edge
/// positions DURING drafting (Inputlog corpora, Conijn et al. 2019). Linear top-to-
/// bottom typing with all edits at the leading edge is the canonical autotype tell
/// that Crossley et al. EDM 2024 specifically flags ("transcribed writing is much
/// more linear").
///
/// Triggers on BOTH sentence boundaries (every "." or "?" or "!" followed by space
/// + capital, or end-of-paragraph) AND paragraph boundaries — sentence-level
/// triggering is critical because short / single-paragraph documents would
/// otherwise see zero mid-draft jumps.
///
/// CRITICAL design point: uses backspace-and-retype, NOT select-and-replace.
/// Backspacing through the word produces N individual delete ops; typing the
/// replacement produces M individual insert ops. That's how a human's edit
/// looks in the OT log. Select-and-replace would produce a single atomic
/// delete-and-insert which is the canonical autotype tell.
///
/// Navigation uses **plain Left arrow × character offset** (not Option+Left × word
/// count). Option+Left's "word boundary" semantics differ across editors — some
/// treat apostrophes, hyphens, or numbers as boundaries differently — which makes
/// it desync from our internal word index and lands the cursor in the wrong place.
/// Plain Left arrow moves exactly one grapheme per press, identical across every
/// macOS app, so we land deterministically. We use a fast auto-repeat-style cadence
/// (`fastArrow`) so the navigation looks like a held key rather than 200 individual
/// taps.
enum MidDraftReviser {
    struct Params {
        /// Per-sentence-boundary probability of injecting a jump.
        var jumpProbabilityPerSentence: Double
        /// Per-paragraph-boundary probability (additive — paragraph boundaries
        /// are also sentence boundaries, so this is the *boost* over the
        /// sentence-level rate).
        var jumpProbabilityParagraphBoost: Double
        /// How many words back from leading edge to target.
        var jumpBackRange: ClosedRange<Int>
        /// Don't jump if total committed words < this.
        var minWordsToInject: Int
        /// Min words between consecutive jumps so they don't pile up.
        var minWordsBetweenJumps: Int
        /// Cap on character-distance to jump back. A 70-word jump back can be
        /// 400+ chars; capping prevents very-long arrow runs that look unnatural.
        var maxJumpBackChars: Int
        var preJumpPauseMs: ClosedRange<Double>
        var preTypePauseMs: ClosedRange<Double>
        var postEditPauseMs: ClosedRange<Double>

        static let standard = Params(
            jumpProbabilityPerSentence: 0.09,
            jumpProbabilityParagraphBoost: 0.20,
            jumpBackRange: 4...35,
            minWordsToInject: 12,
            minWordsBetweenJumps: 18,    // longer cooldown so jumps feel rare
            maxJumpBackChars: 320,
            preJumpPauseMs: 600.0...2800.0,
            preTypePauseMs: 500.0...1800.0,
            postEditPauseMs: 700.0...3000.0
        )

        static let aggressive = Params(
            jumpProbabilityPerSentence: 0.32,
            jumpProbabilityParagraphBoost: 0.55,
            jumpBackRange: 5...60,
            minWordsToInject: 8,
            minWordsBetweenJumps: 8,
            maxJumpBackChars: 500,
            preJumpPauseMs: 800.0...4000.0,
            preTypePauseMs: 700.0...2500.0,
            postEditPauseMs: 1000.0...4500.0
        )
    }

    private struct WordSpan {
        let start: Int   // index into typedBuffer
        let end: Int     // exclusive
    }

    /// Process a [LogicalKey] stream, injecting jump-back-edit-return sequences at
    /// sentence and paragraph boundaries.
    ///
    /// `typedBuffer` is built from the input stream's `.char` and `.backspace`
    /// events AND mutated to reflect each injected replacement, so subsequent
    /// jumps compute their character offsets against the post-edit doc state
    /// rather than a hypothetical buffer that diverges from reality.
    static func inject(
        stream: [LogicalKey],
        params: Params,
        sampler: Sampler
    ) -> [LogicalKey] {
        var out: [LogicalKey] = []
        out.reserveCapacity(stream.count + 64)

        var typedBuffer: [Character] = []
        var prevWasNewline = false
        var wordsCommittedAtLastJump = 0

        for key in stream {
            out.append(key)

            switch key {
            case .char(let c):
                typedBuffer.append(c)
            case .backspace:
                if !typedBuffer.isEmpty { typedBuffer.removeLast() }
            case .extraDelayMs, .rawKey, .fastArrow:
                continue
            }

            // Boundary detection from the COMMITTED typedBuffer:
            //   - paragraph: just appended second \n
            //   - sentence:  just appended a space following ".", "?", "!"
            var isBoundary = false
            var isParagraph = false

            if case .char(let c) = key {
                if c == "\n" {
                    if prevWasNewline {
                        isBoundary = true
                        isParagraph = true
                        prevWasNewline = false
                    } else {
                        prevWasNewline = true
                    }
                } else if c == " " {
                    if typedBuffer.count >= 2 {
                        let prev = typedBuffer[typedBuffer.count - 2]
                        if prev == "." || prev == "?" || prev == "!" {
                            isBoundary = true
                        }
                    }
                    prevWasNewline = false
                } else {
                    prevWasNewline = false
                }
            }

            guard isBoundary else { continue }

            let wordSpans = findWordSpans(in: typedBuffer)
            let wordsCommitted = wordSpans.count
            guard wordsCommitted >= params.minWordsToInject else { continue }
            guard wordsCommitted - wordsCommittedAtLastJump >= params.minWordsBetweenJumps else { continue }

            let p = params.jumpProbabilityPerSentence + (isParagraph ? params.jumpProbabilityParagraphBoost : 0)
            guard sampler.bool(probability: p) else { continue }

            let injected = appendJump(
                typedBuffer: &typedBuffer,
                wordSpans: wordSpans,
                params: params,
                sampler: sampler,
                out: &out
            )
            if injected { wordsCommittedAtLastJump = wordsCommitted }
        }

        return out
    }

    // MARK: - Jump emission

    private static func appendJump(
        typedBuffer: inout [Character],
        wordSpans: [WordSpan],
        params: Params,
        sampler: Sampler,
        out: inout [LogicalKey]
    ) -> Bool {
        let wordsCommitted = wordSpans.count
        let maxAllowed = wordsCommitted - 3   // never touch the last 3 words
        guard maxAllowed >= params.jumpBackRange.lowerBound else { return false }
        let upper = min(maxAllowed, params.jumpBackRange.upperBound)
        let lower = params.jumpBackRange.lowerBound
        guard upper >= lower else { return false }

        // Try a few jump-back distances if the target word is unsuitable
        // (too short / no letters / no synonym available). Bail after a
        // small number of attempts so we don't loop forever.
        for _ in 0..<5 {
            let jumpBack = lower + Int(sampler.uniform() * Double(upper - lower + 1))
            let targetWordIdx = wordsCommitted - jumpBack
            guard targetWordIdx >= 0 && targetWordIdx < wordsCommitted else { continue }

            let span = wordSpans[targetWordIdx]
            let targetWord = String(typedBuffer[span.start..<span.end])
            guard targetWord.count >= 3,
                  targetWord.contains(where: { $0.isLetter }) else { continue }

            let charsFromEndToWordEnd = typedBuffer.count - span.end
            // Cap absolute distance — a 70-word jump back is 400+ chars of
            // arrow nav, which is both slow and unrealistic.
            guard charsFromEndToWordEnd <= params.maxJumpBackChars else { continue }
            // Defensive: never emit a zero-distance jump.
            guard charsFromEndToWordEnd > 0 else { continue }

            let replacement: String = {
                if let alt = SynonymDictionary.shared.pickAlternate(for: targetWord, sampler: sampler) {
                    return matchCase(alt, like: targetWord)
                }
                return targetWord
            }()

            // 1. Pre-jump pause.
            out.append(.extraDelayMs(sampler.uniform(in: params.preJumpPauseMs)))

            // 2. Left arrow × char-distance — relative-to-current navigation
            //    via plain arrow keys. Cursor lands at end of target word.
            for _ in 0..<charsFromEndToWordEnd {
                out.append(.fastArrow(code: Keycodes.leftArrow))
            }

            // 3. Pre-type pause.
            out.append(.extraDelayMs(sampler.uniform(in: params.preTypePauseMs)))

            // 4. Backspace through the word — N individual delete ops.
            for _ in 0..<targetWord.count {
                out.append(.backspace)
            }

            // 5. Type replacement.
            for ch in replacement {
                out.append(.char(ch))
            }

            // 6. Settle pause.
            out.append(.extraDelayMs(sampler.uniform(in: params.postEditPauseMs)))

            // 7. Right arrow × char-distance — return to end of doc. After
            //    backspacing N and typing M chars, distance from cursor to
            //    new end equals the original `charsFromEndToWordEnd`.
            for _ in 0..<charsFromEndToWordEnd {
                out.append(.fastArrow(code: Keycodes.rightArrow))
            }

            // 8. Mutate typedBuffer to reflect the replacement so future
            //    jumps compute character offsets against the real doc state.
            typedBuffer.replaceSubrange(span.start..<span.end, with: Array(replacement))

            return true
        }
        return false
    }

    // MARK: - Helpers

    private static func findWordSpans(in chars: [Character]) -> [WordSpan] {
        var spans: [WordSpan] = []
        var i = 0
        while i < chars.count {
            if chars[i].isLetter || chars[i].isNumber {
                let start = i
                while i < chars.count && (chars[i].isLetter || chars[i].isNumber || chars[i] == "'") {
                    i += 1
                }
                spans.append(WordSpan(start: start, end: i))
            } else {
                i += 1
            }
        }
        return spans
    }

    private static func matchCase(_ alt: String, like original: String) -> String {
        guard let firstO = original.first, let firstA = alt.first else { return alt }
        if firstO.isUppercase {
            return String(firstA.uppercased()) + String(alt.dropFirst())
        }
        if firstA.isUppercase {
            return String(firstA.lowercased()) + String(alt.dropFirst())
        }
        return alt
    }
}
