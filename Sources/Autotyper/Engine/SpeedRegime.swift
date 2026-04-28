import Foundation

/// Slowly-varying multiplier on the base inter-keystroke interval. The single
/// strongest tell of autotyping is *temporal independence*: real typists have
/// streaks of fast keys and streaks of slow keys (positive lag-1 autocorrelation
/// in the IKI series, ~0.3–0.5). Independent lognormal sampling gives zero
/// autocorrelation no matter how wide the per-key variance.
///
/// SpeedRegime fixes that by holding a "current pace" multiplier that persists
/// across many keystrokes, then jumping to a new target every 5–15 keys with a
/// smooth lerp. Range 0.5×–1.6× produces realistic 20–100%+ swings in instantaneous
/// WPM with the right autocorrelation structure.
final class SpeedRegime {
    private var current: Double = 1.0
    private let sampler: Sampler
    private var keysSinceUpdate: Int = 0
    private var nextUpdateAt: Int

    init(sampler: Sampler) {
        self.sampler = sampler
        self.nextUpdateAt = Int(sampler.uniform(in: 5.0...15.0))
    }

    /// Returns the slowdown multiplier to apply to base IKI:
    ///   1.0 = baseline pace
    ///   1.8 = 80% slower than baseline (a slow stretch)
    ///   0.4 = 60% faster than baseline (a fast burst)
    func nextSlowdown() -> Double {
        keysSinceUpdate += 1
        if keysSinceUpdate >= nextUpdateAt {
            // Wider target range (0.4–1.8) and sharper transitions (alpha 0.55–0.95)
            // produce visibly larger WPM swings. Previously the smooth lerp made
            // changes too gradual to be obvious to a viewer.
            let raw = 1.0 + sampler.normal() * 0.40
            let target = max(0.40, min(1.80, raw))
            let alpha = sampler.uniform(in: 0.55...0.95)
            current = current + (target - current) * alpha

            // 12% chance of a "shock" — instantaneous jump to a markedly different
            // pace. Models the human moment of "oh wait" or "ok now I'm warmed up."
            if sampler.bool(probability: 0.12) {
                current = sampler.uniform(in: 0.45...1.70)
            }

            keysSinceUpdate = 0
            nextUpdateAt = Int(sampler.uniform(in: 4.0...12.0))
        }
        return current
    }

    var debugCurrent: Double { current }
}
