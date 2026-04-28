import Foundation

/// SplitMix64-based seedable RNG. Swift's SystemRandomNumberGenerator isn't seedable
/// and we need reproducibility for tests/debugging — same paste + same seed should
/// produce the same plan.
struct SeedableRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

final class Sampler {
    private var rng: SeedableRNG
    private var spareNormal: Double?

    /// seed=nil draws a fresh nondeterministic seed; otherwise the run is reproducible.
    init(seed: UInt64? = nil) {
        let actualSeed = seed ?? UInt64.random(in: 1...UInt64.max)
        self.rng = SeedableRNG(seed: actualSeed)
    }

    func uniform() -> Double {
        let n = rng.next()
        return Double(n >> 11) / Double(1 << 53)
    }

    func uniform(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + uniform() * (range.upperBound - range.lowerBound)
    }

    func bool(probability p: Double) -> Bool { uniform() < p }

    func pick<T>(_ items: [T]) -> T { items[Int(uniform() * Double(items.count))] }

    /// Standard normal via Box-Muller, caching the second draw.
    func normal() -> Double {
        if let s = spareNormal { spareNormal = nil; return s }
        var u1 = uniform()
        let u2 = uniform()
        if u1 < 1e-12 { u1 = 1e-12 }
        let r = (-2.0 * log(u1)).squareRoot()
        let theta = 2.0 * .pi * u2
        spareNormal = r * sin(theta)
        return r * cos(theta)
    }

    /// Lognormal where the resulting distribution has *mean* `mean` (not median).
    /// μ = ln(mean) − σ²/2, then sample exp(μ + σZ).
    func lognormal(mean: Double, sigma: Double) -> Double {
        let mu = log(max(mean, 1e-6)) - sigma * sigma / 2.0
        return exp(mu + sigma * normal())
    }

    func lognormalClamped(mean: Double, sigma: Double, lower: Double, upper: Double) -> Double {
        min(max(lognormal(mean: mean, sigma: sigma), lower), upper)
    }
}
