import Foundation

/// Splits raw text into a [TextScript] sequence, deciding probabilistically which
/// words to second-guess. Vocabulary dwelling is a powerful tell of human
/// composition that no autotyper currently simulates.
enum SynonymDweller {
    struct Params {
        var rate: Double                    // base per-eligible-word probability
        var paragraphStartBoost: Double     // multiplier for first-word-of-paragraph
        var oncePerSentence: Bool

        static let defaults = Params(
            rate: 0.03,
            paragraphStartBoost: 1.6,
            oncePerSentence: true
        )
    }

    static func split(text: String, params: Params, sampler: Sampler) -> [TextScript] {
        let dict = SynonymDictionary.shared
        let chars = Array(text)
        var scripts: [TextScript] = []
        var runStart = 0
        var i = 0
        var sentenceHasDwell = false
        var atParagraphStart = true

        // Pre-scan word spans to know paragraph/sentence positions.
        let wordSpans = scanWordSpans(chars: chars)
        var spanIdx = 0

        while i < chars.count {
            // Sync sentenceHasDwell at sentence terminators.
            let c = chars[i]
            if c == "." || c == "!" || c == "?" {
                sentenceHasDwell = false
                atParagraphStart = false
            }
            if c == "\n", i + 1 < chars.count, chars[i + 1] == "\n" {
                atParagraphStart = true
                sentenceHasDwell = false
            }

            // Advance spanIdx until pointing at a span that starts at i (if any).
            while spanIdx < wordSpans.count && wordSpans[spanIdx].end <= i {
                spanIdx += 1
            }

            // Are we at the start of a word that's eligible for dwelling?
            if spanIdx < wordSpans.count, wordSpans[spanIdx].start == i {
                let span = wordSpans[spanIdx]
                let word = String(chars[span.start..<span.end])

                // Skip first/last word of paragraph per plan constraints.
                let isFirstInParagraph = atParagraphStart
                let isLastInParagraph = isLastWordInParagraph(span: span, allSpans: wordSpans, currentIdx: spanIdx, chars: chars)
                let alreadyDwelledInSentence = params.oncePerSentence && sentenceHasDwell

                if !isLastInParagraph && !alreadyDwelledInSentence,
                   let alternate = dict.pickAlternate(for: word, sampler: sampler) {
                    let rate = params.rate * (isFirstInParagraph ? params.paragraphStartBoost : 1.0)
                    if sampler.bool(probability: rate) {
                        // Emit pending run, then dwell.
                        if span.start > runStart {
                            scripts.append(.run(String(chars[runStart..<span.start])))
                        }
                        // Preserve case of first letter — match original word's case.
                        let casedAlternate = matchCase(alternate, like: word)
                        scripts.append(.dwell(typed: casedAlternate, then: word))
                        runStart = span.end
                        i = span.end
                        sentenceHasDwell = true
                        atParagraphStart = false
                        continue
                    }
                }
            }

            if c.isLetter || c == "'" {
                // mid-word, skip ahead — no special handling needed, runStart covers it
            } else if !c.isWhitespace {
                atParagraphStart = false
            }

            i += 1
        }

        if runStart < chars.count {
            scripts.append(.run(String(chars[runStart..<chars.count])))
        }
        return scripts
    }

    private struct Span { let start: Int; let end: Int }

    private static func scanWordSpans(chars: [Character]) -> [Span] {
        var spans: [Span] = []
        var i = 0
        while i < chars.count {
            if chars[i].isLetter {
                var j = i
                while j < chars.count && (chars[j].isLetter || chars[j] == "'") { j += 1 }
                spans.append(Span(start: i, end: j))
                i = j
            } else {
                i += 1
            }
        }
        return spans
    }

    private static func isLastWordInParagraph(span: Span, allSpans: [Span], currentIdx: Int, chars: [Character]) -> Bool {
        // Look for next span. If between this span's end and the next span's start
        // (or end of text) we encounter "\n\n", this is the last word of the paragraph.
        let nextStart = currentIdx + 1 < allSpans.count ? allSpans[currentIdx + 1].start : chars.count
        var sawNewline = false
        var k = span.end
        while k < nextStart {
            if chars[k] == "\n" {
                if sawNewline { return true }
                sawNewline = true
            } else if !chars[k].isWhitespace {
                sawNewline = false
            }
            k += 1
        }
        // If we reach end of text without a next span, this is the last word.
        if currentIdx + 1 >= allSpans.count { return true }
        return false
    }

    private static func matchCase(_ alternate: String, like original: String) -> String {
        guard let firstAlt = alternate.first, let firstOrig = original.first else { return alternate }
        if firstOrig.isUppercase {
            return String(firstAlt.uppercased()) + String(alternate.dropFirst())
        }
        if firstAlt.isUppercase {
            return String(firstAlt.lowercased()) + String(alternate.dropFirst())
        }
        return alternate
    }
}
