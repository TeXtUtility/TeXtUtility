import Foundation

/// Loads synonyms.txt into a word → group lookup. Each line of the resource file is
/// a comma-separated synonym group: `begin,start,commence,initiate`.
final class SynonymDictionary {
    static let shared = SynonymDictionary()

    private let groups: [[String]]
    /// lowercased word → indices into `groups`
    private let index: [String: Int]

    private init() {
        guard let url = Bundle.module.url(forResource: "synonyms", withExtension: "txt"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            self.groups = []
            self.index = [:]
            return
        }
        var loadedGroups: [[String]] = []
        var idx: [String: Int] = [:]
        for raw in contents.split(whereSeparator: { $0.isNewline }) {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let words = line.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces).lowercased()
            }.filter { !$0.isEmpty }
            if words.count < 2 { continue }
            let groupIdx = loadedGroups.count
            loadedGroups.append(words)
            for w in words { idx[w] = groupIdx }
        }
        self.groups = loadedGroups
        self.index = idx
    }

    /// If `word` is in any group, return the group; otherwise nil. Case-insensitive.
    func group(for word: String) -> [String]? {
        guard let i = index[word.lowercased()] else { return nil }
        return groups[i]
    }

    /// Pick a plausible alternate to `word` from its group. Constraints from the plan:
    ///   - Length within 4 of the original (avoids weird spacing).
    ///   - Prefer same first letter when possible.
    ///   - Never the original word itself.
    /// Returns nil if no acceptable alternate exists.
    func pickAlternate(for word: String, sampler: Sampler) -> String? {
        guard let g = group(for: word) else { return nil }
        let lower = word.lowercased()
        let candidates = g.filter { other in
            other != lower
                && abs(other.count - word.count) <= 4
                && !other.contains(" ")  // skip multi-word synonyms; can't backspace cleanly
        }
        if candidates.isEmpty { return nil }
        // Two-tier: prefer same-first-letter.
        let firstLetter = lower.first
        let preferred = candidates.filter { $0.first == firstLetter }
        let pool = preferred.isEmpty ? candidates : preferred
        return sampler.pick(pool)
    }
}
