import Foundation

/// QWERTY-adjacent keys for "fat finger" typos. When the typo injector commits an
/// insertion or substitution error, it picks an adjacent key — that's what real fat-
/// finger errors look like. Random uniform-from-alphabet substitutions don't match
/// any real keystroke-error distribution.
enum QwertyAdjacency {
    private static let map: [Character: [Character]] = [
        "q": ["w", "a"],
        "w": ["q", "e", "a", "s"],
        "e": ["w", "r", "s", "d"],
        "r": ["e", "t", "d", "f"],
        "t": ["r", "y", "f", "g"],
        "y": ["t", "u", "g", "h"],
        "u": ["y", "i", "h", "j"],
        "i": ["u", "o", "j", "k"],
        "o": ["i", "p", "k", "l"],
        "p": ["o", "l"],
        "a": ["q", "w", "s", "z"],
        "s": ["a", "w", "e", "d", "z", "x"],
        "d": ["s", "e", "r", "f", "x", "c"],
        "f": ["d", "r", "t", "g", "c", "v"],
        "g": ["f", "t", "y", "h", "v", "b"],
        "h": ["g", "y", "u", "j", "b", "n"],
        "j": ["h", "u", "i", "k", "n", "m"],
        "k": ["j", "i", "o", "l", "m"],
        "l": ["k", "o", "p"],
        "z": ["a", "s", "x"],
        "x": ["z", "s", "d", "c"],
        "c": ["x", "d", "f", "v"],
        "v": ["c", "f", "g", "b"],
        "b": ["v", "g", "h", "n"],
        "n": ["b", "h", "j", "m"],
        "m": ["n", "j", "k"],
    ]

    /// Pick a random adjacent key for `c`. Preserves case. Returns nil for non-letters.
    static func adjacent(of c: Character, sampler: Sampler) -> Character? {
        let lower = Character(c.lowercased())
        guard let neighbors = map[lower], !neighbors.isEmpty else { return nil }
        let pick = sampler.pick(neighbors)
        return c.isUppercase ? Character(pick.uppercased()) : pick
    }
}
