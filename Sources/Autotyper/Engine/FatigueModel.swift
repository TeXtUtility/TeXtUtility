import Foundation

/// Late-essay fatigue. Real long-form drafting shows a U-curve in care: cautious
/// opening, fluent middle, sloppier-and-less-revised end. We currently only
/// model the end-of-session drift — in the final fraction of the source text,
/// error rate climbs and mid-draft revision rate drops, mimicking the typist's
/// declining attention as they push toward "done."
///
/// The effect is gated on session length. Below `minTextChars` it's disabled
/// entirely (a 500-word note doesn't run long enough for fatigue to plausibly
/// set in). Between `minTextChars` and `fullTextChars` the magnitude ramps
/// linearly, so a 700-word and 1400-word essay don't sit on opposite sides of
/// a hard cliff; full strength applies above `fullTextChars`.
struct FatigueParams {
    /// Minimum source length (characters) for any fatigue effect. Below this:
    /// zero modulation.
    var minTextChars: Int
    /// Source length at which fatigue is at full strength. Between
    /// `minTextChars` and this value the effect ramps linearly.
    var fullTextChars: Int
    /// Fraction of the session that's the "fatigue tail" (e.g., 0.20 = the
    /// last fifth). Inside the tail, the multiplier ramps from 1.0 at the
    /// start of the tail to its end value at session-end.
    var fatigueStartFraction: Double
    /// Error-rate multiplier at the very end of the session. Linearly
    /// interpolated from 1.0 over the tail.
    var errorMultiplierAtEnd: Double
    /// Mid-draft jump-probability multiplier at the very end. Same ramp.
    /// Below 1.0 because a tired writer revises less, not more.
    var revisionMultiplierAtEnd: Double

    static let standard = FatigueParams(
        minTextChars: 3500,            // ~700 words: below this, no fatigue
        fullTextChars: 7000,           // ~1400 words: full fatigue
        fatigueStartFraction: 0.20,    // last fifth of the session
        errorMultiplierAtEnd: 1.75,    // 75% more typos at the end
        revisionMultiplierAtEnd: 0.35  // ~third the revision rate
    )
}

enum FatigueModel {
    /// Session-length intensity: 0 below `minTextChars`, 1 at or above
    /// `fullTextChars`, linear in between.
    static func intensity(totalChars: Int, params: FatigueParams) -> Double {
        let n = Double(totalChars)
        let lo = Double(params.minTextChars)
        let hi = Double(params.fullTextChars)
        if n <= lo { return 0 }
        if n >= hi { return 1 }
        return (n - lo) / (hi - lo)
    }

    /// Multiplier for an effect that ramps from 1.0 to `endValue` across
    /// the tail of the session. Returns 1.0 outside the tail. The full
    /// in-tail multiplier is itself scaled by session-length intensity, so
    /// borderline-length essays get a softened version of the effect.
    static func multiplier(
        progress: Double,
        intensity: Double,
        params: FatigueParams,
        endValue: Double
    ) -> Double {
        if intensity <= 0 { return 1.0 }
        let fatigueStart = 1.0 - params.fatigueStartFraction
        if progress < fatigueStart { return 1.0 }
        let fatigueProgress = min(1.0, (progress - fatigueStart) / params.fatigueStartFraction)
        let fullMult = 1.0 + fatigueProgress * (endValue - 1.0)
        return 1.0 + intensity * (fullMult - 1.0)
    }
}
