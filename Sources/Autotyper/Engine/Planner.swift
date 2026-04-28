import Foundation
import CoreGraphics

/// Profile parameters as a flat struct so the Planner doesn't depend on UI types.
struct ProfileParams {
    var targetWpm: Double
    var dwellMeanMs: Double
    var bigramStrength: Double
    var ikiSigma: Double            // lognormal σ for inter-keystroke interval
    var dwellSigma: Double
    var fatiguePerMin: Double       // multiplicative drift (e.g. 0.0015 = 0.15%/min)
    var warmupKeys: Int
    var warmupFloor: Double         // starting multiplier, ramps to 1.0
    var burstWordsRange: ClosedRange<Int>
    var burstPauseMeanMs: Double
    var errorRate: Double           // per-letter base typo probability
    var backspaceIkiMs: Double      // flat IKI for rapid backspace bursts
    var synonymDwellRate: Double    // per-eligible-word probability
    /// Within-word speedup multiplier (applied when previous char was also a letter).
    /// Real typing is bimodal: ~80–150 ms IKI within words, 300–500 ms between
    /// words. Without this distinction, every char ends up in its own Google Docs
    /// OT op instead of chunking 3–5 chars per op the way real typing does.
    /// Range 0.45–0.75; lower = sharper bursts.
    var withinWordSpeedup: Double

    static let medium = ProfileParams(
        targetWpm: 55,
        dwellMeanMs: 75,
        bigramStrength: 1.0,
        ikiSigma: 0.55,
        dwellSigma: 0.25,
        fatiguePerMin: 0.0015,
        warmupKeys: 50,
        warmupFloor: 0.85,
        burstWordsRange: 3...8,
        burstPauseMeanMs: 320,
        errorRate: 0.018,
        backspaceIkiMs: 95,
        synonymDwellRate: 0.020,
        withinWordSpeedup: 0.60   // mid-word chars at 60% of base IKI
    )

    static func from(_ kind: ProfileKind) -> ProfileParams {
        switch kind {
        case .huntPeck:
            // Hunt-peck typists don't do fast bursts at all — every keystroke
            // is a deliberate single act. So withinWordSpeedup is barely below 1.
            var p = medium
            p.targetWpm = 22
            p.dwellMeanMs = 100
            p.bigramStrength = 1.15
            p.ikiSigma = 0.55
            p.errorRate = 0.032
            p.backspaceIkiMs = 130
            p.synonymDwellRate = 0.0
            p.burstWordsRange = 2...5
            p.burstPauseMeanMs = 500
            p.withinWordSpeedup = 0.85
            return p
        case .thoughtful:
            var p = medium
            p.targetWpm = 35
            p.dwellMeanMs = 90
            p.bigramStrength = 1.05
            p.errorRate = 0.026
            p.backspaceIkiMs = 110
            p.synonymDwellRate = 0.035
            p.withinWordSpeedup = 0.68
            return p
        case .casual:
            var p = medium
            p.targetWpm = 45
            p.dwellMeanMs = 80
            p.bigramStrength = 1.00
            p.errorRate = 0.022
            p.backspaceIkiMs = 100
            p.synonymDwellRate = 0.018
            p.withinWordSpeedup = 0.62
            return p
        case .medium:
            return medium
        case .office:
            var p = medium
            p.targetWpm = 65
            p.dwellMeanMs = 70
            p.bigramStrength = 0.95
            p.errorRate = 0.015
            p.backspaceIkiMs = 90
            p.synonymDwellRate = 0.015
            p.withinWordSpeedup = 0.55
            return p
        case .fluent:
            var p = medium
            p.targetWpm = 75
            p.dwellMeanMs = 65
            p.bigramStrength = 0.92
            p.errorRate = 0.012
            p.backspaceIkiMs = 85
            p.synonymDwellRate = 0.012
            p.withinWordSpeedup = 0.50
            return p
        case .fast:
            var p = medium
            p.targetWpm = 85
            p.dwellMeanMs = 60
            p.bigramStrength = 0.90
            p.errorRate = 0.010
            p.backspaceIkiMs = 80
            p.synonymDwellRate = 0.010
            p.withinWordSpeedup = 0.48
            return p
        case .touchTypist:
            // Expert touch typists have the most pronounced within-word bursts:
            // 3–6 chars at sub-100ms IKI is normal, separated by clear word-
            // boundary pauses.
            var p = medium
            p.targetWpm = 95
            p.dwellMeanMs = 55
            p.bigramStrength = 0.85
            p.ikiSigma = 0.35
            p.errorRate = 0.007
            p.backspaceIkiMs = 75
            p.synonymDwellRate = 0.006
            p.burstWordsRange = 5...10
            p.burstPauseMeanMs = 220
            p.withinWordSpeedup = 0.42
            return p
        }
    }
}

enum Planner {
    static let backspaceKeycode: CGKeyCode = 51

    /// One-stop entry: text → KeyEvents with all human-typing layers applied.
    ///
    /// Default pipeline:
    ///   text → SynonymDweller → [TextScript]
    ///        → TypoInjector  → [LogicalKey]
    ///        → planFromStream → [KeyEvent]
    ///
    /// Essay mode adds typing-time layers that target GPTZero / Revision
    /// History / Draftback Writing-Replay detectors reading the Google Docs
    /// OT log:
    ///   + SessionPacer    — multi-minute breaks at paragraph boundaries
    ///   + MidDraftReviser — mid-document jump-back-edit-return cursor jumps
    ///   + DurationTargeter — scales pauses so total time matches realistic
    ///                        ~19 WPM composition speed (Brown 1988)
    static func plan(
        text: String,
        profile: ProfileParams,
        essayMode: Bool,
        sampler: Sampler
    ) -> [KeyEvent] {
        let synonymParams = SynonymDweller.Params(
            rate: profile.synonymDwellRate,
            paragraphStartBoost: 1.6,
            oncePerSentence: true
        )
        let scripts = SynonymDweller.split(text: text, params: synonymParams, sampler: sampler)

        let typoParams = TypoInjector.Params(
            baseErrorRate: profile.errorRate,
            recognitionMeanMs: 250,
            recognitionSigma: 0.5,
            allowOnFirstChar: false
        )
        var stream = TypoInjector.toLogicalKeys(scripts: scripts, params: typoParams, sampler: sampler)

        if essayMode {
            stream = SessionPacer.inject(
                stream: stream,
                params: .standard,
                sampler: sampler
            )
            // Mid-draft cursor jumps — highest-impact countermeasure against
            // Writing-Replay detectors (Crossley 2024 EDM): authentic essays
            // show 25–40% of insertions at non-leading-edge positions during
            // drafting.
            stream = MidDraftReviser.inject(
                stream: stream,
                params: .standard,
                sampler: sampler
            )
            // Stretch existing pauses so total session ≈ realistic composition
            // pace (~45 s per 100 chars including breaks).
            let avgIki = 60_000.0 / (profile.targetWpm * 5.0)
            stream = DurationTargeter.scale(
                stream: stream,
                params: .realistic,
                avgIkiMs: avgIki
            )
        }

        return planFromStream(stream, profile: profile, sampler: sampler)
    }

    /// Walk a [LogicalKey] stream and emit timed KeyEvents.
    static func planFromStream(
        _ stream: [LogicalKey],
        profile: ProfileParams,
        sampler: Sampler
    ) -> [KeyEvent] {
        var out: [KeyEvent] = []
        out.reserveCapacity(stream.count)

        let baseIki = 60_000.0 / (profile.targetWpm * 5.0)
        let regime = SpeedRegime(sampler: sampler)
        var prevTyped: Character? = nil
        var keyIndex = 0
        var elapsedMs: Double = 0
        var pendingExtraMs: Double = 0
        var wordsSinceBurst = 0
        var nextBurstWordCount = sampler.pick(Array(profile.burstWordsRange))
        var inBackspaceBurst = false

        // "Review pause": every 30–80 typed chars, the typist briefly stops to read
        // back what they wrote — a 500–2500 ms hesitation. Major contributor to
        // realistic temporal structure that detection systems flag the absence of.
        var keysUntilReview = Int(sampler.uniform(in: 30.0...80.0))

        // Word-level complexity state. At each word boundary we look ahead in the
        // stream to compute the upcoming word's complexity, then apply (a) an onset
        // pause to the first character and (b) a within-word slowdown to all of
        // its letters. Detection literature flags the absence of this pattern.
        //
        // ALSO tracks position within the word for end-of-word motor rolloff
        // (Crump & Logan): skilled typists pre-load the last 2–3 keys of a word
        // and execute them noticeably faster than the word's average IKI. Without
        // this, per-word timing looks unnaturally uniform.
        var currentWordSlowdown: Double = 1.0
        var currentWordLength: Int = 0
        var currentWordPosition: Int = 0
        var streamIdx = 0

        // Phrase-level acceleration. Real composition has rhythm: typist starts a
        // sentence carefully (planning the first words), then accelerates as they
        // hit cruising speed mid-sentence. Word index within the current phrase
        // (resets on . ? ! or paragraph break) drives a gentle slowdown for the
        // first few words.
        var wordsInPhrase = 0

        for key in stream {
            defer { streamIdx += 1 }
            switch key {
            case .extraDelayMs(let ms):
                pendingExtraMs += ms

            case .backspace:
                let pausePart = pendingExtraMs
                let iki = profile.backspaceIkiMs + pausePart
                pendingExtraMs = 0
                let dwell = sampler.lognormalClamped(
                    mean: profile.dwellMeanMs * 0.85,
                    sigma: profile.dwellSigma,
                    lower: 35,
                    upper: 150
                )
                out.append(KeyEvent(
                    action: .tap(code: backspaceKeycode, modifiers: []),
                    delayBeforeMs: iki,
                    pauseMs: pausePart,
                    dwellMs: dwell
                ))
                elapsedMs += iki + dwell
                keyIndex += 1
                inBackspaceBurst = true
                // Backspaces don't update prevTyped — we want bigram timing on the
                // resumed character to relate to whatever was typed before the burst.

            case .rawKey(let code, let mods):
                // Arrow nav, word jumps, Find (⌘F), selection extends. Real
                // users hit these at hand-speed (250-450 ms per press), slower
                // than typing. Don't apply bigram/word logic.
                let pausePart = pendingExtraMs
                let iki = sampler.lognormalClamped(
                    mean: 320, sigma: 0.4, lower: 150, upper: 1200
                ) + pausePart
                pendingExtraMs = 0
                let dwell = sampler.lognormalClamped(
                    mean: profile.dwellMeanMs, sigma: profile.dwellSigma, lower: 40, upper: 180
                )
                out.append(KeyEvent(
                    action: .tap(code: code, modifiers: mods),
                    delayBeforeMs: iki,
                    pauseMs: pausePart,
                    dwellMs: dwell
                ))
                elapsedMs += iki + dwell
                keyIndex += 1
                // Don't update prevTyped — arrow nav doesn't change the bigram context.

            case .fastArrow(let code):
                // Held-arrow auto-repeat. macOS auto-repeat at default settings
                // is ~30 ms per repeat after the initial 250 ms hold. We model
                // this with a tight lognormal centered at 32 ms.
                let pausePart = pendingExtraMs
                let iki = sampler.lognormalClamped(
                    mean: 32, sigma: 0.18, lower: 22, upper: 60
                ) + pausePart
                pendingExtraMs = 0
                let dwell = sampler.lognormalClamped(
                    mean: 24, sigma: 0.18, lower: 15, upper: 50
                )
                out.append(KeyEvent(
                    action: .tap(code: code, modifiers: []),
                    delayBeforeMs: iki,
                    pauseMs: pausePart,
                    dwellMs: dwell
                ))
                elapsedMs += iki + dwell
                keyIndex += 1

            case .char(let c):
                // After a backspace burst, treat the next char as a fresh start
                // (no bigram penalty against the backspace).
                let prevForBigram = inBackspaceBurst ? nil : prevTyped
                inBackspaceBurst = false

                // Word-boundary detection: this char starts a new word if it's a
                // letter and the previous typed char wasn't.
                let isWordStart = c.isLetter && !(prevTyped?.isLetter ?? false)
                var wordOnsetExtra: Double = 0
                if isWordStart {
                    let upcomingWord = lookaheadWord(stream: stream, from: streamIdx)
                    let complexity = WordComplexity.score(for: upcomingWord)
                    currentWordSlowdown = WordComplexity.withinWordSlowdown(complexity: complexity)
                    wordOnsetExtra = WordComplexity.onsetPauseMs(complexity: complexity)
                    currentWordLength = upcomingWord.count
                    currentWordPosition = 0
                    wordsInPhrase += 1

                    // Random extended pause before long words. Real typists
                    // visibly hesitate before unfamiliar/uncommon long words —
                    // they're "previewing the spelling" mentally before committing.
                    // Probability scales with word length, with the tail going
                    // up to a few seconds for very long words.
                    if upcomingWord.count >= 11, sampler.bool(probability: 0.22) {
                        wordOnsetExtra += sampler.uniform(in: 1800.0...4500.0)
                    } else if upcomingWord.count >= 9, sampler.bool(probability: 0.13) {
                        wordOnsetExtra += sampler.uniform(in: 1100.0...2800.0)
                    } else if upcomingWord.count >= 7, sampler.bool(probability: 0.06) {
                        wordOnsetExtra += sampler.uniform(in: 700.0...1900.0)
                    }
                } else if !c.isLetter {
                    currentWordSlowdown = 1.0
                    currentWordLength = 0
                    currentWordPosition = 0
                }
                // Reset phrase counter at sentence terminators.
                if c == "." || c == "?" || c == "!" {
                    wordsInPhrase = 0
                }

                // End-of-word motor rolloff. Last 1–3 chars of a word are typed
                // noticeably faster than the average IKI because the typist's
                // fingers are pre-loaded for the word's known ending. Without
                // this, words feel artificially "draft-mode-uniform" — every
                // letter taking the same time, which is a tell.
                var rolloffMult: Double = 1.0
                if c.isLetter && currentWordLength >= 4 {
                    let posFromEnd = currentWordLength - currentWordPosition - 1
                    if currentWordLength >= 6 {
                        switch posFromEnd {
                        case 0: rolloffMult = 0.62
                        case 1: rolloffMult = 0.72
                        case 2: rolloffMult = 0.86
                        default: break
                        }
                    } else {
                        // Shorter words (4–5 chars): gentler rolloff so they
                        // don't all become a single fast blur.
                        switch posFromEnd {
                        case 0: rolloffMult = 0.78
                        case 1: rolloffMult = 0.92
                        default: break
                        }
                    }
                }

                // Burst-pause rhythm at word completion.
                var burstExtra: Double = 0
                if c == " ", let p = prevTyped, p != " " {
                    wordsSinceBurst += 1
                    if wordsSinceBurst >= nextBurstWordCount {
                        burstExtra = sampler.lognormalClamped(
                            mean: profile.burstPauseMeanMs,
                            sigma: 0.4,
                            lower: 100,
                            upper: 800
                        )
                        wordsSinceBurst = 0
                        nextBurstWordCount = sampler.pick(Array(profile.burstWordsRange))
                    }
                }

                // Mid-word "thinking" pause: only on genuinely long words
                // (9+ chars), where a brief mid-spelling hesitation is plausible.
                // Short words type as a single motor burst — pausing inside
                // them is the unnatural-feeling tell.
                var thinkingExtra: Double = 0
                let isMidWord = c.isLetter && (prevTyped?.isLetter ?? false)
                if isMidWord && currentWordLength >= 9 && sampler.bool(probability: 0.012) {
                    thinkingExtra = sampler.lognormalClamped(
                        mean: 320, sigma: 0.5, lower: 180, upper: 900
                    )
                }

                // Periodic review pause — "stopping to re-read." Countdown
                // ticks every char, but the pause is deferred until the next
                // word boundary (space or newline) so we never freeze halfway
                // through a word.
                var reviewExtra: Double = 0
                keysUntilReview -= 1
                let atReviewBoundary = c == " " || c == "\n"
                if keysUntilReview <= 0 && atReviewBoundary {
                    if sampler.bool(probability: 0.20) {
                        reviewExtra = sampler.lognormalClamped(
                            mean: 3000, sigma: 0.40, lower: 1800, upper: 6000
                        )
                    } else {
                        reviewExtra = sampler.lognormalClamped(
                            mean: 1000, sigma: 0.45, lower: 400, upper: 2500
                        )
                    }
                    keysUntilReview = Int(sampler.uniform(in: 22.0...60.0))
                }

                guard let (code, needsShift) = KeycodeMap.keycode(for: c) else {
                    // Unmapped char — Phase 6 will route through Unicode fallback.
                    // For now, drop it and keep the IKI accounting intact.
                    continue
                }
                let mods: CGEventFlags = needsShift ? [.maskShift] : []

                let bigram = BigramTable.multiplier(prev: prevForBigram, current: c, strength: profile.bigramStrength)
                let warmup: Double = {
                    if keyIndex >= profile.warmupKeys { return 1.0 }
                    let frac = Double(keyIndex) / Double(profile.warmupKeys)
                    return profile.warmupFloor + (1.0 - profile.warmupFloor) * frac
                }()
                let fatigue = 1.0 + profile.fatiguePerMin * (elapsedMs / 60_000.0)
                let regimeSlowdown = regime.nextSlowdown()

                // Within-word speedup: real typing is bimodal — fast bursts within
                // words (80–150 ms IKI), real pauses at word boundaries (300–500
                // ms). This is critical for Google Docs OT op chunking: chars
                // typed within ~100 ms get batched into a single op (the "mar"
                // and "ked" chunks the user actually sees in Writing Replay
                // playback). Without this, each char gets its own op.
                let withinWordMult: Double = {
                    guard let p = prevTyped, p.isLetter, c.isLetter else { return 1.0 }
                    return profile.withinWordSpeedup
                }()

                // Phrase acceleration: typist starts a sentence carefully and
                // speeds up as they get into rhythm. First word ~15% slower,
                // ramping back to baseline by word 5.
                let phraseAccel: Double = {
                    switch wordsInPhrase {
                    case 1: return 1.15
                    case 2: return 1.09
                    case 3: return 1.04
                    case 4: return 1.02
                    default: return 1.0
                    }
                }()

                // Composition: macro pace × bigram × warmup × fatigue × word
                // complexity × rolloff × within-word burst × phrase-acceleration.
                let mu = baseIki * bigram * warmup * fatigue * regimeSlowdown * currentWordSlowdown * rolloffMult * withinWordMult * phraseAccel
                // Clamp the typing-rhythm portion to a reasonable range. The
                // pause portion (`pausePart` below) is allowed to be arbitrarily
                // long so multi-minute SessionPacer breaks are honored as-is
                // instead of being silently truncated to 25 s.
                let typingPart = min(max(sampler.lognormal(mean: mu, sigma: profile.ikiSigma), 5), 25_000)
                let pausePart = BigramTable.boundaryPauseMs(prev: prevForBigram, current: c, sampler: sampler)
                              + wordOnsetExtra
                              + burstExtra
                              + thinkingExtra
                              + reviewExtra
                              + pendingExtraMs
                pendingExtraMs = 0
                let iki = typingPart + pausePart

                let dwell = sampler.lognormalClamped(
                    mean: profile.dwellMeanMs,
                    sigma: profile.dwellSigma,
                    lower: 40,
                    upper: 180
                )

                out.append(KeyEvent(
                    action: .tap(code: code, modifiers: mods),
                    delayBeforeMs: iki,
                    pauseMs: pausePart,
                    dwellMs: dwell
                ))

                elapsedMs += iki + dwell
                keyIndex += 1
                prevTyped = c
                if c.isLetter { currentWordPosition += 1 }
            }
        }

        // Detect paragraph breaks (\n\n in original text) and inject heavy-tailed
        // pauses. We do this in a post-pass so the typo injector stays oblivious to
        // structural pauses.
        // (Heuristic: look for two adjacent newline KeyEvents and pad the second.)
        return injectParagraphBreaks(out, sampler: sampler)
    }

    /// Scan forward from `idx` to reconstruct the word the typist is about to type.
    /// Stops at the first non-letter `.char`. Skips delays and tracks backspaces by
    /// dropping the previous letter — so the reconstructed word reflects the final
    /// committed sequence after typo correction, which is the typist's actual target.
    private static func lookaheadWord(stream: [LogicalKey], from idx: Int, maxScan: Int = 32) -> String {
        var word = ""
        let end = min(idx + maxScan, stream.count)
        var i = idx
        while i < end {
            switch stream[i] {
            case .char(let c):
                if c.isLetter {
                    word.append(c)
                } else {
                    return word
                }
            case .backspace:
                if !word.isEmpty { word.removeLast() }
            case .extraDelayMs, .rawKey, .fastArrow:
                break
            }
            i += 1
        }
        return word
    }

    private static func injectParagraphBreaks(_ events: [KeyEvent], sampler: Sampler) -> [KeyEvent] {
        var out = events
        let returnCode = KeycodeMap.keycode(for: "\n")?.code ?? 36
        var i = 1
        while i < out.count {
            let prev = out[i - 1]
            let curr = out[i]
            if case .tap(let pc, _) = prev.action, case .tap(let cc, _) = curr.action,
               pc == returnCode, cc == returnCode {
                let extra = BigramTable.paragraphBreakMs(sampler: sampler)
                out[i] = KeyEvent(
                    action: curr.action,
                    delayBeforeMs: curr.delayBeforeMs + extra,
                    pauseMs: curr.pauseMs + extra,
                    dwellMs: curr.dwellMs
                )
            }
            i += 1
        }
        return out
    }
}
