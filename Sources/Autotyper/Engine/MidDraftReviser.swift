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
/// `Shift+Option+Right` then typing a replacement produces a single atomic
/// delete-and-insert OT op in Google Docs — the canonical autotype tell that
/// Writing Replay flags as "large text insertion." Backspacing through the word
/// produces N individual delete ops; typing the replacement produces M individual
/// insert ops. That's how a human's edit looks in the OT log.
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
        var preJumpPauseMs: ClosedRange<Double>
        var preTypePauseMs: ClosedRange<Double>
        var postEditPauseMs: ClosedRange<Double>

        static let standard = Params(
            jumpProbabilityPerSentence: 0.09,
            jumpProbabilityParagraphBoost: 0.20,
            jumpBackRange: 4...35,
            minWordsToInject: 12,
            minWordsBetweenJumps: 18,    // longer cooldown so jumps feel rare
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
            preJumpPauseMs: 800.0...4000.0,
            preTypePauseMs: 700.0...2500.0,
            postEditPauseMs: 1000.0...4500.0
        )
    }

    /// Process a [LogicalKey] stream, injecting jump-back-edit-return sequences at
    /// sentence and paragraph boundaries.
    static func inject(
        stream: [LogicalKey],
        text: String,
        params: Params,
        sampler: Sampler
    ) -> [LogicalKey] {
        let allWords = extractWords(text)
        guard !allWords.isEmpty else { return stream }

        var out: [LogicalKey] = []
        out.reserveCapacity(stream.count + 64)

        var typedBuffer = ""
        var prevWasNewline = false
        var wordsCommittedAtLastJump = 0

        for key in stream {
            out.append(key)

            switch key {
            case .char(let c):
                typedBuffer.append(c)
            case .backspace:
                if !typedBuffer.isEmpty { typedBuffer.removeLast() }
            case .extraDelayMs, .rawKey:
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
                    let last2 = typedBuffer.suffix(3).dropLast()  // chars before this space
                    if let prev = last2.last, ".?!".contains(prev) {
                        isBoundary = true
                    }
                    prevWasNewline = false
                } else {
                    prevWasNewline = false
                }
            }

            guard isBoundary else { continue }

            // Compute words committed to typedBuffer.
            let wordsCommitted = countWords(in: typedBuffer)
            guard wordsCommitted >= params.minWordsToInject else { continue }
            guard wordsCommitted - wordsCommittedAtLastJump >= params.minWordsBetweenJumps else { continue }

            let p = params.jumpProbabilityPerSentence + (isParagraph ? params.jumpProbabilityParagraphBoost : 0)
            guard sampler.bool(probability: p) else { continue }

            let injected = appendJump(
                wordsCommitted: wordsCommitted,
                allWords: allWords,
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
        wordsCommitted: Int,
        allWords: [String],
        params: Params,
        sampler: Sampler,
        out: inout [LogicalKey]
    ) -> Bool {
        let maxAllowed = wordsCommitted - 3
        guard maxAllowed >= params.jumpBackRange.lowerBound else { return false }
        let upper = min(maxAllowed, params.jumpBackRange.upperBound)
        let lower = params.jumpBackRange.lowerBound
        guard upper >= lower else { return false }
        let jumpBack = lower + Int(sampler.uniform() * Double(upper - lower + 1))

        let targetIdx = wordsCommitted - jumpBack
        guard targetIdx >= 0 && targetIdx < allWords.count else { return false }
        let targetWord = allWords[targetIdx]

        guard targetWord.count >= 3,
              targetWord.contains(where: { $0.isLetter }) else { return false }

        let replacement: String = {
            if let alt = SynonymDictionary.shared.pickAlternate(for: targetWord, sampler: sampler) {
                return matchCase(alt, like: targetWord)
            }
            return targetWord
        }()

        // 1. Pre-jump pause.
        out.append(.extraDelayMs(sampler.uniform(in: params.preJumpPauseMs)))

        // 2. Option+Left × jumpBack — navigate to start of target word.
        for _ in 0..<jumpBack {
            out.append(.rawKey(code: Keycodes.leftArrow, modifiers: [.maskAlternate]))
        }

        // 3. Option+Right (no shift) — jump to END of target word, ready to backspace.
        out.append(.rawKey(code: Keycodes.rightArrow, modifiers: [.maskAlternate]))

        // 4. Pre-type pause.
        out.append(.extraDelayMs(sampler.uniform(in: params.preTypePauseMs)))

        // 5. Backspace through the word — N individual delete ops, no atomic op.
        for _ in 0..<targetWord.count {
            out.append(.backspace)
        }

        // 6. Type replacement.
        for ch in replacement {
            out.append(.char(ch))
        }

        // 7. Settle pause.
        out.append(.extraDelayMs(sampler.uniform(in: params.postEditPauseMs)))

        // 8. ⌘↓ — return cursor to end of doc.
        out.append(.rawKey(code: Keycodes.downArrow, modifiers: [.maskCommand]))

        return true
    }

    // MARK: - Helpers

    private static func extractWords(_ text: String) -> [String] {
        var out: [String] = []
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            if chars[i].isLetter || chars[i].isNumber {
                var j = i
                while j < chars.count && (chars[j].isLetter || chars[j].isNumber || chars[j] == "'") {
                    j += 1
                }
                out.append(String(chars[i..<j]))
                i = j
            } else {
                i += 1
            }
        }
        return out
    }

    private static func countWords(in text: String) -> Int {
        var count = 0
        var inWord = false
        for c in text {
            if c.isLetter || c.isNumber {
                if !inWord {
                    count += 1
                    inWord = true
                }
            } else {
                inWord = false
            }
        }
        return count
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
