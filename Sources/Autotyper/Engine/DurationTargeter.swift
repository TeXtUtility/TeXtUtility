import Foundation

/// Scales the IKI of a [LogicalKey] stream (specifically the `.extraDelayMs` entries
/// for now — per-key IKI is determined by the planner, but the macro pauses are
/// what most influence total session duration) to hit a realistic target time.
///
/// Empirical research (Hayes & Flower; Inputlog studies on student writing): real
/// students take 25–60 minutes for a 500-word essay including all breaks and
/// revisions — i.e. ~3–7 seconds per word averaged across the whole session.
/// Without this scaling, the autotyper completes a 500-word essay in 6–12 minutes
/// even with all the per-keystroke realism, which is itself a flag.
///
/// We scale only the explicit pause events (extraDelayMs from boundary, session,
/// and review pauses), leaving the per-key IKI alone — the per-key timing should
/// stay close to the profile's WPM target, but the *total session shape* is
/// extended via longer pauses.
enum DurationTargeter {
    struct Params {
        /// Target session duration in seconds per 100 typed characters
        /// (chars, not words; chars are easier to count in a stream).
        /// Real essays: ~30-90 seconds per 100 chars including breaks.
        var targetSecondsPer100Chars: Double
        /// Maximum scale-up factor. Don't more-than-double pauses.
        var maxScaleFactor: Double
        /// Don't scale below this (so fast profiles aren't artificially slowed).
        var minScaleFactor: Double

        static let realistic = Params(
            targetSecondsPer100Chars: 45.0,    // ~7.5 min per 100 words
            maxScaleFactor: 2.5,
            minScaleFactor: 0.7
        )

        static let casual = Params(
            targetSecondsPer100Chars: 30.0,
            maxScaleFactor: 2.0,
            minScaleFactor: 0.7
        )

        static let off = Params(
            targetSecondsPer100Chars: 0,       // 0 = disable scaling
            maxScaleFactor: 1.0,
            minScaleFactor: 1.0
        )
    }

    /// Compute the predicted total duration (sum of all pause and IKI times) given
    /// a [LogicalKey] stream and the profile's average IKI. Scale `extraDelayMs`
    /// entries proportionally so total matches target.
    static func scale(
        stream: [LogicalKey],
        params: Params,
        avgIkiMs: Double
    ) -> [LogicalKey] {
        guard params.targetSecondsPer100Chars > 0 else { return stream }

        // Count chars and total existing extraDelay time.
        var charCount = 0
        var existingExtraMs: Double = 0
        for key in stream {
            switch key {
            case .char: charCount += 1
            case .backspace: charCount += 1
            case .rawKey: charCount += 1
            case .extraDelayMs(let ms): existingExtraMs += ms
            }
        }
        guard charCount > 10 else { return stream }

        // Predicted IKI time (rough — ignores bigram/regime variance, but those
        // average out in expectation).
        let predictedIkiMs = Double(charCount) * avgIkiMs
        let predictedTotalMs = predictedIkiMs + existingExtraMs

        // Target.
        let targetMs = (params.targetSecondsPer100Chars * 1000.0) * (Double(charCount) / 100.0)

        // If we're already at or above target, don't change anything.
        guard targetMs > predictedTotalMs else { return stream }

        // Scale only the extraDelay portion. New extraDelay total = targetMs - predictedIkiMs.
        // Scale factor = newTotal / existingTotal.
        guard existingExtraMs > 0 else {
            // No existing pauses — can't stretch by scaling. Caller should add
            // pauses (via SessionPacer / boundary pauses) to enable this path.
            return stream
        }
        let needed = max(0, targetMs - predictedIkiMs)
        var factor = needed / existingExtraMs
        factor = min(params.maxScaleFactor, max(params.minScaleFactor, factor))

        // Apply.
        return stream.map { key -> LogicalKey in
            if case .extraDelayMs(let ms) = key {
                return .extraDelayMs(ms * factor)
            }
            return key
        }
    }
}
