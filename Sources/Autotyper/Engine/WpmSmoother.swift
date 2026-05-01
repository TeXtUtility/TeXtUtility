import Foundation

/// Downsamples and smooths a dense WPM time series for display. The Executor
/// emits roughly one sample per second of active typing — fine for short runs,
/// but a 30-minute session produces ~1800 points that overwhelm SwiftUI Charts
/// in a 480-pt-wide popover (the line gets visually compressed and high-
/// frequency fluctuation makes the trend illegible).
///
/// `smooth(samples:targetPoints:)` bins the input series into roughly
/// `targetPoints` equal-time-width buckets, averages the WPM values within each
/// bucket (this is the primary smoothing pass), then applies a 3-tap moving
/// average across non-empty bucket centers to round off the remaining
/// per-bucket noise. Empty buckets (long pauses where no samples landed) are
/// dropped rather than zero-filled, so the rendered line bridges the gap
/// instead of dipping to zero.
///
/// Sessions whose raw sample count is already at or below `targetPoints` are
/// returned unmodified — there's nothing useful binning can do at that scale.
enum WpmSmoother {
    /// Default display target. ~150 points fits the popover width with one
    /// pixel per ~3 horizontal points and is plenty of resolution for the eye.
    static let defaultTargetPoints = 150

    static func smooth(samples raw: [WpmSample], targetPoints: Int = defaultTargetPoints) -> [WpmSample] {
        guard raw.count > targetPoints, targetPoints >= 4 else { return raw }
        guard let first = raw.first, let last = raw.last else { return raw }
        let totalRange = last.elapsed - first.elapsed
        guard totalRange > 0 else { return raw }

        let bucketSize = totalRange / Double(targetPoints)
        var sums: [Double] = Array(repeating: 0, count: targetPoints)
        var counts: [Int] = Array(repeating: 0, count: targetPoints)
        for s in raw {
            let raw = (s.elapsed - first.elapsed) / bucketSize
            let idx = max(0, min(targetPoints - 1, Int(raw)))
            sums[idx] += s.wpm
            counts[idx] += 1
        }

        // 3-tap centered moving average across non-empty buckets. We rebuild
        // the `means` array from `sums/counts` first so neighbor lookups during
        // smoothing read from the unsmoothed pass.
        var means: [Double?] = Array(repeating: nil, count: targetPoints)
        for i in 0..<targetPoints where counts[i] > 0 {
            means[i] = sums[i] / Double(counts[i])
        }

        var out: [WpmSample] = []
        out.reserveCapacity(targetPoints)
        for i in 0..<targetPoints {
            guard means[i] != nil else { continue }
            var acc: Double = 0
            var n: Int = 0
            for j in max(0, i - 1)...min(targetPoints - 1, i + 1) {
                if let v = means[j] { acc += v; n += 1 }
            }
            let avg = acc / Double(n)
            let t = first.elapsed + (Double(i) + 0.5) * bucketSize
            out.append(WpmSample(elapsed: t, wpm: avg))
        }
        return out
    }
}
