import Foundation

/// Loads and exposes the top-N common English words, used by TypoInjector to
/// apply word-frequency-aware error rates.
///
/// Real humans blast through familiar high-frequency words — that's where most
/// typos happen — *and* are caught fastest because the word is so familiar that
/// the visual mismatch is instant. Long unfamiliar words get typed more carefully
/// and recognized more slowly when wrong.
enum CommonWords {
    static let set: Set<String> = {
        guard let url = Bundle.module.url(forResource: "common_words", withExtension: "txt"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return Set(contents.split(whereSeparator: { $0.isNewline }).map { String($0).lowercased() })
    }()

    enum Class { case common, neutral, longUncommon }

    /// Classify the word for error-rate adjustment.
    static func classify(_ word: String) -> Class {
        let lower = word.lowercased()
        if set.contains(lower) { return .common }
        if lower.count >= 8 { return .longUncommon }
        return .neutral
    }

    /// Multipliers per the plan:
    ///   common:        error_rate ×1.8, recognition ×0.5 (fast catch)
    ///   long uncommon: error_rate ×0.7, recognition ×1.4 (careful, slow catch)
    ///   neutral:       baseline
    static func errorRateMultiplier(for cls: Class) -> Double {
        switch cls {
        case .common: return 1.8
        case .longUncommon: return 0.7
        case .neutral: return 1.0
        }
    }

    static func recognitionMultiplier(for cls: Class) -> Double {
        switch cls {
        case .common: return 0.5
        case .longUncommon: return 1.4
        case .neutral: return 1.0
        }
    }
}
