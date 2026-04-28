import Foundation

/// Inserts multi-minute "session breaks" into the LogicalKey stream at paragraph
/// boundaries — the kind of pauses that show up as gaps in a Google Docs Writing
/// Replay timeline. Without these, the document grows continuously over a single
/// 8-15 minute span, which is the single most reliable autotype tell that
/// revision-history detectors flag.
///
/// Real student essay sessions are punctuated by 1–10 minute breaks: phone check,
/// stretch, fridge, look at notes, return. We sample from a heavy-tailed
/// distribution so most breaks are 1–3 minutes but ~10% extend to 5–10 minutes,
/// matching the empirical writing-process literature.
enum SessionPacer {
    struct Params {
        /// How many paragraph boundaries to skip between session breaks.
        var paragraphsBetweenBreaks: ClosedRange<Int>
        /// Lognormal mean for break length (ms).
        var breakMeanMs: Double
        var breakSigma: Double
        var minBreakMs: Double
        var maxBreakMs: Double
        /// Probability of a much longer break ("got distracted") on any given
        /// scheduled break — gives the heavy tail.
        var longTailProbability: Double
        var longTailMeanMs: Double
        var longTailMaxMs: Double

        static let standard = Params(
            paragraphsBetweenBreaks: 2...4,
            breakMeanMs: 90_000,        // 90 s typical
            breakSigma: 0.55,
            minBreakMs: 25_000,         // 25 s minimum
            maxBreakMs: 240_000,        // 4 min cap on regular breaks
            longTailProbability: 0.18,
            longTailMeanMs: 360_000,    // 6 min mean for long breaks
            longTailMaxMs: 900_000      // 15 min cap
        )

        static let aggressive = Params(
            paragraphsBetweenBreaks: 1...3,
            breakMeanMs: 150_000,
            breakSigma: 0.55,
            minBreakMs: 45_000,
            maxBreakMs: 360_000,
            longTailProbability: 0.30,
            longTailMeanMs: 540_000,
            longTailMaxMs: 1_500_000
        )

        static let minimal = Params(
            paragraphsBetweenBreaks: 4...8,
            breakMeanMs: 30_000,
            breakSigma: 0.50,
            minBreakMs: 10_000,
            maxBreakMs: 90_000,
            longTailProbability: 0.05,
            longTailMeanMs: 180_000,
            longTailMaxMs: 360_000
        )
    }

    /// Insert `.extraDelayMs` events at selected paragraph boundaries.
    static func inject(
        stream: [LogicalKey],
        params: Params,
        sampler: Sampler
    ) -> [LogicalKey] {
        var out: [LogicalKey] = []
        out.reserveCapacity(stream.count + 16)

        var paragraphsSinceBreak = 0
        var nextBreakAfter = sampler.pick(Array(params.paragraphsBetweenBreaks))
        var prevWasNewline = false

        for key in stream {
            out.append(key)

            // Detect "\n\n" — second newline after another newline = paragraph break.
            if case .char(let c) = key, c == "\n" {
                if prevWasNewline {
                    paragraphsSinceBreak += 1
                    if paragraphsSinceBreak >= nextBreakAfter {
                        let breakMs = sampleBreakDuration(params: params, sampler: sampler)
                        out.append(.extraDelayMs(breakMs))
                        paragraphsSinceBreak = 0
                        nextBreakAfter = sampler.pick(Array(params.paragraphsBetweenBreaks))
                    }
                    prevWasNewline = false
                } else {
                    prevWasNewline = true
                }
            } else if case .extraDelayMs = key {
                // pass through, don't reset prev-newline tracking
            } else {
                prevWasNewline = false
            }
        }

        return out
    }

    private static func sampleBreakDuration(params: Params, sampler: Sampler) -> Double {
        if sampler.bool(probability: params.longTailProbability) {
            return sampler.lognormalClamped(
                mean: params.longTailMeanMs,
                sigma: 0.55,
                lower: params.maxBreakMs,
                upper: params.longTailMaxMs
            )
        } else {
            return sampler.lognormalClamped(
                mean: params.breakMeanMs,
                sigma: params.breakSigma,
                lower: params.minBreakMs,
                upper: params.maxBreakMs
            )
        }
    }
}
