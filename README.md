<p align="center">
  <img src="banner.png" alt="" width="520">
</p>

<p align="center">
  <em>A native macOS menu-bar utility that types pasted text into the focused window with the cadence, rhythm, and edit patterns of a real human.</em>
</p>

<p align="center">
  <a href="#install">Install</a> ·
  <a href="#use">Use</a> ·
  <a href="#how-it-works">How&nbsp;it&nbsp;works</a> ·
  <a href="#fidelity">Fidelity stack</a> ·
  <a href="#privacy--safety">Safety</a> ·
  <a href="#acknowledgments">Acknowledgments</a>
</p>

---

## What it does

Paste text. Pick a typist profile. Hit start, focus the target window during a 3-second countdown, and the text is typed for you, keystroke by keystroke, with realistic timing, occasional typos that get corrected, and (in essay mode) the kind of mid-draft revisions and re-reading pauses that real people produce.

The output is **indistinguishable from human typing** down to the per-keystroke timing distribution and the operational-transformation log of collaborative editors. Models and parameters are calibrated against published typing-behavior research (Aalto 136M-keystroke corpus, Inputlog studies, motor-control experiments).

## Use cases

- **Accessibility.** Composing a long document via switch input, eye gaze, or speech-to-text is slow. Drafting in a comfortable editor and then having TeXtUtility type the text into the destination at a natural cadence is more ergonomic than instant paste, especially for forms and editors that visibly chunk pasted blocks.
- **Tutorial recording and demos.** Screencasts where text appears instantaneously feel mechanical. TeXtUtility produces typing that reads as authentic on playback without the recording artist hand-typing every example.
- **Form filling for input-validating services.** Some web forms throttle, animate against, or reject instant-paste input; TeXtUtility's per-keystroke pacing satisfies those checks.
- **Application QA.** Testing keyboard-handling code paths, debouncing logic, autosave timing, and IME interactions benefits from realistic input streams rather than uniform 10ms-spaced events.
- **Writing-process replay.** Reproducing realistic drafting patterns (mid-document edits, vocabulary substitutions, session breaks) for research demos or teaching.
- **Free and Open Source.** TeXtUtility is licensed under the MIT License.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/TeXtUtility/TeXtUtility/main/install.sh | bash
```

*Re-run any time to update or repair the installation.*

## Use

1. Click the keyboard icon in your menu bar to open the popover.
2. Paste your text into the editor, or drop in plain text from another app.
3. Select a **profile**, the persona that controls speed, error rate, and feel:

    | Profile | WPM | Texture |
    |---|---|---|
    | Hunt-Peck | 22 | Beginner, frequent pauses, lots of corrections |
    | Thoughtful | 35 | Deliberate composer; vocabulary second-guessing |
    | Casual | 45 | Average adult typist |
    | Medium | 55 | Standard touch typist *(default)* |
    | Office | 65 | Programmer, fluent and accurate |
    | Fluent | 75 | Confident touch typist |
    | Fast | 85 | Skilled, quick, low-error |
    | Touch-Typist | 95 | Expert, near-flawless |

4. Toggle **Essay mode** on for long-form composition (adds session breaks, mid-draft edits, and a pacing layer that targets ~19 WPM net composition speed, the realistic rate for actual writing including thinking time).
5. Click **Start typing in 3s**. During the 3-second countdown, focus the target window. That captures the destination PID, and keystrokes will be delivered to it for the entire session even if you switch focus elsewhere.
6. Wait. The menu-bar icon shows live progress while typing, and a pause icon with a live countdown to the next keystroke whenever the executor is in a pause — sentence boundaries, paragraph breaks, review re-reads, word-onset hesitations, mid-draft jump pauses, and multi-minute session breaks all surface as "1s" / "12s" / "1:30" countdowns. When done, a white checkmark flashes three times and stays solid; click the icon to open the post-session stats panel (WPM line chart, total time, character/word counts, deletions, edit operations).

### Pausing and stopping

- **Pause / resume in-app**: ⌘P (or the Pause / Resume button). The executor stalls between events, holding any in-flight break timer steady; tapping ⌘P again resumes from the same point.
- **Pause / resume globally**: **⌥⌘P**, recognized by the same event tap that handles the panic chord — works from any app while typing is in flight.
- **Stop in-app**: ⌘. (or the Stop button)
- **Stop globally** (from any app, instant): **⌥⌘.**. A global event tap intercepts the chord even while typing is in flight.

## How it works

```
┌──────────────────────────────────────────────────────────────────┐
│  Pasted text                                                     │
└────────────────────────────────────────────────────────────────┬─┘
                                                                 │
                                                                 ▼
                                                ┌───────────────────────────────┐
                                                │ SynonymDweller                │
                                                │  pick eligible words, type    │
                                                │  the synonym then revise to   │
                                                │  the original                 │
                                                └───────────────┬───────────────┘
                                                                ▼
                                                ┌───────────────────────────────┐
                                                │ TypoInjector                  │
                                                │  insertion / substitution /   │
                                                │  omission / transposition     │
                                                │  with recognition delay and   │
                                                │  backspace burst              │
                                                └───────────────┬───────────────┘
                                                                ▼  (essay mode)
                                                ┌───────────────────────────────┐
                                                │ SessionPacer · MidDraftReviser│
                                                │ DurationTargeter              │
                                                └───────────────┬───────────────┘
                                                                ▼
                                                ┌───────────────────────────────┐
                                                │ Planner.planFromStream        │
                                                │  bigram timing · within-word  │
                                                │  bursts · word-onset pauses · │
                                                │  end-of-word rolloff · review │
                                                │  pauses · phrase acceleration │
                                                └───────────────┬───────────────┘
                                                                ▼
                                                ┌───────────────────────────────┐
                                                │ Executor                      │
                                                │  CGEventPostToPid →           │
                                                │  target application           │
                                                └───────────────────────────────┘
```

Each layer adds one slice of human typing texture; the final stream is a list of timed CGEvents posted directly to the captured target process via `CGEventPostToPid`. PID-targeting (rather than focus-relative posting) means the user can switch focus to other apps during typing without redirecting the keystrokes.

## Fidelity

The high-level promise, *indistinguishable from human typing*, is built on a stack of independently calibrated effects, each grounded in published research on typing behavior or writing process. Together they reproduce the timing distributions, error patterns, and edit operations that human typists generate, both at the per-keystroke level and at the session/document level.

### Per-keystroke timing

| Effect | Description |
|---|---|
| **Profile-baseline IKI** | Inter-keystroke interval drawn from a lognormal distribution centered on `60_000 / (WPM × 5)`, the baseline mean for the chosen typist persona. |
| **Bigram modulation** | Same-finger and same-hand bigrams (e.g., `ed`, `as`) are slower; alternating-hand bigrams (e.g., `th`, `is`) are faster. Multipliers from the Aalto 136M-keystroke dataset.<sup>[1]</sup> |
| **Within-word burst** | Letters typed mid-word are 0.42×–0.85× the baseline IKI (profile-dependent). Real touch typists fire 3–6 keys at sub-100ms IKI within a word, separated by 300–500ms between-word pauses. Without this, every char ends up in its own operational-transformation chunk in collaborative editors. |
| **End-of-word motor rolloff** | The last 1–3 letters of a word are typed faster than the word's average IKI; the typist's fingers are pre-loaded for the known ending. From Crump & Logan's hierarchical control experiments.<sup>[2]</sup> |
| **Word-onset pause** | First letter of a long or uncommon word gets an extra "previewing the spelling" pause (probabilistic, scaling with word length up to several seconds for very long words). |
| **Phrase acceleration** | First 1–4 words of a sentence are 2–15% slower than baseline; speed ramps to baseline by word 5. Real composition starts cautiously and accelerates as rhythm sets in. |
| **Warmup ramp** | First 50 keys of a session are slightly slower (profile-dependent floor 0.42–0.85), ramping linearly to baseline. |
| **Fatigue drift** | Multiplicative slowdown of ~0.15%/minute over the session, a small effect but noticeable over essays of 20+ minutes. |
| **Dwell time** | Lognormal hold-down time per key (mean 55–100ms profile-dependent), with separate mean/sigma for backspaces (faster and more consistent; backspace bursts are motor-programmatic, not deliberate). |
| **Boundary pauses** | Sentence boundaries (after `.` `?` `!`) get 0.75–2.0s pauses with a small heavy tail; commas 250–1800ms; paragraph breaks 0.8–2.5s. Modeled after pause distributions in writing-process keystroke logs.<sup>[3]</sup> |
| **Periodic review pauses** | Every 22–60 characters, a deferred pause fires at the next word boundary: 80% chance of a 0.4–2.5s "re-reading" hesitation, 20% chance of a 1.8–6s "thinking" pause. Reproduces the bursty WPM distribution real composition produces. |
| **Mid-word thinking** | On long words (≥9 chars only), 1.2% chance of a brief 180–900ms hesitation between letters, modeling spelling uncertainty without producing the unnatural mid-word pauses that small-probability distributions over short words would create. |

### Error model

Typo distribution from the writing-process literature: 60% insertion, 20% substitution, 15% omission, 5% transposition.<sup>[3]</sup>

| Type | Behavior |
|---|---|
| **Insertion** | Type a QWERTY-adjacent wrong key before the correct one; continue 0–4 chars; recognize; backspace; retype correctly. |
| **Substitution** | Type a QWERTY-adjacent wrong key in place of the intended one; continue 0–2 chars; recognize; backspace; retype. |
| **Omission** | Skip the intended letter, type the next 1–3 chars; recognize; backspace; retype the omitted letter and what followed. |
| **Transposition** | Type next-letter-then-current-letter; continue 0–2 chars; recognize; backspace; retype correctly. |

Recognition delay is lognormal with mean 250ms scaled by **word frequency**: very common words (`the`, `and`) are caught instantly; uncommon polysyllabic words take 250–500ms longer. Common-word error rate is also higher (motor automation overshoots), uncommon-word error rate is lower (deliberate typing).

Per-letter base error rate is profile-dependent: 0.7% for Touch-Typist, 3.2% for Hunt-Peck. The base rate is further modulated by the late-essay fatigue model on long sessions — error rate climbs across the final 20% of the source, ramping to ~1.75× by the closing keystroke.

### Vocabulary dwelling

Per eligible word, with profile-dependent probability (0.6–3.5%, max one per sentence), the typist:

1. Types a synonym from a 1819-entry curated dictionary.
2. Pauses 400–3500ms (the "wait, that's not the word I meant" beat).
3. Backspaces it.
4. Types the original word.

Dictionary covers ~2400 unique words across academic vocabulary, common verbs, common nouns, adjectives, adverbs, transitional connectors, and quantifiers. Synonyms are filtered to length-similar single words, with same-first-letter alternatives preferred where available.

### Mid-draft editing (essay mode)

At sentence and paragraph boundaries, with calibrated probability (9% per sentence, +20% at paragraph breaks, ≥18 words between consecutive jumps):

1. Pause 0.6–2.8s.
2. `Left arrow` ×N to walk back exactly N characters from the cursor's current position, where N is the precise grapheme distance to the end of the chosen target word (4–35 words back). Plain `Left arrow` is used instead of `Option+Left` because the word-boundary semantics of `Option+Left` differ across editors (apostrophes, hyphens, numbers, punctuation can be treated differently), which previously caused the cursor to land in the wrong position and inserted edits at unintended points. Single-character relative navigation lands deterministically in every macOS app. The arrow run uses an auto-repeat-style cadence (~30ms inter-press) so the navigation reads as a held key rather than a flurry of taps.
3. Pause 0.5–1.8s.
4. Backspace through the word **character by character** (not via select-and-replace; character-by-character produces N individual delete operations in collaborative-editor logs, matching real human edits, rather than a single atomic delete-insert).
5. Type the synonym (or retype the same word; the delete+insert pair is what matters).
6. Pause 0.7–3.0s.
7. `Right arrow` ×N to return the cursor to the end of the document. After backspacing N chars and typing M new ones, distance from cursor to the new end equals the original character offset, so the same N right-arrow presses land cleanly back at the leading edge.

The reviser also mutates its internal model of the typed buffer to reflect each replacement, so subsequent jumps compute their character offsets against the post-edit document state rather than a hypothetical buffer that has diverged from what was actually typed.

On long sessions, the per-boundary jump probability is scaled down across the final 20% of the source via the late-essay fatigue model, reflecting the universal observation that tired writers stop revising and just push for the finish line.

### Late-essay fatigue (long sessions only)

Real long-form drafting shows a U-curve in care: cautious opening, fluent middle, sloppier-and-less-revised end. The fatigue model captures the end-of-session drift — across the final 20% of the source, error rate climbs and mid-draft revision rate drops, mimicking the typist's declining attention as they push toward "done." Specifically, at the closing keystroke:

- Per-letter error rate is multiplied by **~1.75×**
- Mid-draft jump probability is multiplied by **~0.35×**

Both effects ramp linearly from 1.0 over the tail, so a position 90% through the source is at half-strength fatigue (roughly 1.375× error, 0.675× revision) and the end is at full strength.

The effect is **gated on session length**:

- **Below ~700 words (3500 chars)**: zero modulation. A short note doesn't run long enough for fatigue to plausibly set in, and applying the effect to it would produce noticeable end-of-text artifacts on a session a real human would type without a coffee break.
- **Between ~700 and ~1400 words**: the magnitude scales linearly so a 700-word and 1400-word essay don't sit on opposite sides of a hard cliff.
- **Above ~1400 words**: full strength.

The revision-rate ramp only fires when essay mode is on (the mid-draft reviser is essay-mode-only). The error-rate ramp applies regardless of essay mode — fatigue is a typing-behavior effect, not strictly an anti-detection one.

The 25–40% rate of non-leading-edge insertions during drafting is a well-documented signature of authentic writing process.<sup>[4]</sup>

### Session pacing (essay mode)

`SessionPacer` injects multi-minute breaks at paragraph boundaries from a heavy-tailed distribution:

- 70% of breaks: 25s–4min (lognormal mean 90s), typical micro-break, phone glance, sip of coffee.
- 30% of breaks: 5–15min (lognormal mean 6min), the "got distracted" tail. Empirically present in writing-session keystroke logs.<sup>[3]</sup>

### Composition-time targeting (essay mode)

`DurationTargeter` rescales all pauses so the total session time matches realistic composition rate (~19 WPM net including thinking and breaks, a constant well-documented in writing-process research.<sup>[5]</sup>) The raw 55–95 WPM of the typing model would otherwise produce sessions far shorter than authentic drafts of equivalent length.

### Chinese (Mandarin via pinyin)

When the pasted source contains hanzi, TeXtUtility automatically routes it through a pinyin path so a pinyin IME running in the target app can convert the typed pinyin back into characters. The popover shows a "Chinese detected — typing via pinyin" hint as soon as hanzi appear in the input, so you know to switch your IME on before hitting Start.

Each hanzi is transliterated to its base-letters Mandarin pinyin (no tone marks) and followed by a space, which is the gesture most pinyin IMEs use to commit the first candidate:

- `你好`         → `ni hao ` (typed; IME converts back to `你好`)
- `我喜欢学习中文。` → `wo xi huan xue xi zhong wen .`

CJK punctuation (`。`, `，`, `！`, `？`, fullwidth digits, etc.) is converted to its ASCII equivalent so the IME maps it back to the matching Chinese form. ASCII / Latin characters in mixed text (`Hello 你好`) pass through unchanged.

The transliteration uses the standard ICU MandarinLatin transform shipped with macOS — no external pinyin dictionary is bundled. The transform picks the most common reading for polyphones (`行` = xíng / háng, `重` = zhòng / chóng), so the IME may produce a different character than intended in those edge cases. Most common hanzi are unambiguous.

When the Chinese path is active the English-only realism layers are skipped because their models don't translate:

- **Typo injection** is off — QWERTY-adjacency wrong-key swaps would produce wrong pinyin syllables that the IME can't recover from gracefully.
- **Mid-draft revisions** are off — the word-boundary detection relies on English-letter-class transitions and the synonym dictionary is English-only.
- **Synonym dwelling** is off for the same reason.

What stays on: the per-keystroke timing model (baseline IKI, dwell, warmup, fatigue, regime drift, end-of-word rolloff), `SessionPacer` paragraph breaks, and `DurationTargeter` total-session targeting — all language-agnostic. Bigram timing also stays on and naturally produces plausible per-syllable bursts on the expanded pinyin: `ni` types as a within-word burst, the trailing space sits at word-boundary speed, the next syllable starts fresh.

You'll need a pinyin IME enabled in the target app — macOS ships one in **System Settings → Keyboard → Input Sources → Pinyin – Simplified**. Switch the input source to Pinyin in the target app before clicking Start. The 3-second countdown and PID-capture flow are unchanged.

### Operational-transformation considerations

In collaborative editors, every keystroke produces an operation in the document's revision log. Several fidelity choices are specifically designed so the resulting log is indistinguishable from human authoring:

- Within-word bursts at sub-100ms IKI cause the editor to chunk 3–5 chars into single OT operations (matching the granularity human typing produces) rather than emitting one op per keystroke.
- Mid-draft edits use **backspace-through-word** rather than select-and-replace because the latter produces a single atomic delete-insert op, which is the canonical tell of automated input.
- Synonym dwell produces a delete+insert pair scattered through the timeline rather than at the leading edge, matching the temporal distribution of real edits.
- Long inter-paragraph pauses produce visible gaps in the writing-replay timeline that authentic writing sessions universally exhibit.

### Safety against unintended input

- **Global panic chord ⌥⌘.** installs a process-wide CGEvent tap on launch that watches for the chord regardless of focused app. Triggers an abort within ~50ms.
- **Global pause chord ⌥⌘P** uses the same tap to flip a pause flag on the executor, which stalls between events without dropping any state. The pause holds in-flight break timers steady; tapping the chord (or the in-app Pause button / ⌘P) again resumes from the same point.
- **Modifier guard**: on session end (normal or aborted), explicitly releases all modifier keys to ensure no modifiers are left "stuck down" in the target app.
- **Focus capture is a one-time decision**: the destination PID is captured at the end of the 3-second countdown; events go to that PID for the entire session via `CGEventPostToPid`, so the user can switch focus freely without redirecting typing.

## Architecture

| Module | Role |
|---|---|
| [`Planner`](Sources/Autotyper/Engine/Planner.swift) | Top-level orchestrator. Composes the layers below into a single timed `[KeyEvent]` plan. |
| [`SynonymDweller`](Sources/Autotyper/Engine/SynonymDweller.swift) | Picks eligible words, emits dwell-revise sequences. |
| [`SynonymDictionary`](Sources/Autotyper/Engine/SynonymDictionary.swift) | Loads `synonyms.txt`, filters length-similar single-word alternates. |
| [`TypoInjector`](Sources/Autotyper/Engine/TypoInjector.swift) | Splices typo + recognition + backspace + retype sequences. |
| [`QwertyAdjacency`](Sources/Autotyper/Engine/QwertyAdjacency.swift) | Adjacent-key lookup for plausible wrong-key selection. |
| [`CommonWords`](Sources/Autotyper/Engine/CommonWords.swift) | Word frequency classification, drives error-rate and recognition-delay multipliers. |
| [`WordComplexity`](Sources/Autotyper/Engine/WordComplexity.swift) | Word complexity scoring, drives within-word slowdown and onset pause. |
| [`BigramTable`](Sources/Autotyper/Engine/BigramTable.swift) | Per-bigram IKI multipliers; sentence/paragraph boundary pause sampling. |
| [`SpeedRegime`](Sources/Autotyper/Engine/SpeedRegime.swift) | Slow/fast regime alternation with per-regime persistence. |
| [`MidDraftReviser`](Sources/Autotyper/Engine/MidDraftReviser.swift) | Sentence/paragraph-boundary jump-back-edit-return sequences. |
| [`SessionPacer`](Sources/Autotyper/Engine/SessionPacer.swift) | Multi-minute paragraph-boundary breaks. |
| [`DurationTargeter`](Sources/Autotyper/Engine/DurationTargeter.swift) | Total-session-time rescaling. |
| [`FatigueModel`](Sources/Autotyper/Engine/FatigueModel.swift) | Long-session error-rate ramp-up and revision-rate ramp-down across the final 20% of the source. |
| [`PinyinTransliterator`](Sources/Autotyper/Engine/PinyinTransliterator.swift) | Hanzi detection and Mandarin → ASCII pinyin expansion for the Chinese-via-IME path. |
| [`Sampler`](Sources/Autotyper/Engine/Sampler.swift) | Seeded RNG for reproducible plans. |
| [`Executor`](Sources/Autotyper/Executor/Executor.swift) | Walks the plan, posts CGEvents to the target PID. |
| [`KeycodeMap`](Sources/Autotyper/Executor/KeycodeMap.swift) | Character → virtual keycode + shift-required lookup. |
| [`SafetyController`](Sources/Autotyper/Safety/SafetyController.swift) | Global panic-chord event tap. |
| [`AccessibilityCheck`](Sources/Autotyper/Permissions/AccessibilityCheck.swift) | TCC trust-state introspection and prompt. |

## Privacy & safety

- **Zero network activity.** No telemetry, no auto-update, no remote logging. The app communicates only with the macOS event subsystem.
- **No third-party dependencies.** The entire codebase compiles against Apple frameworks alone (SwiftUI, AppKit, CoreGraphics, ApplicationServices, Charts). No external Swift packages.
- **No file writes outside the app bundle.** TeXtUtility does not save text to disk, does not log keystrokes, and does not persist the contents of the input field across launches.
- **PID-targeted event delivery** prevents accidental keystrokes into a different app: once the session begins, events go to the captured PID regardless of which window has focus.
- **Global panic chord ⌥⌘.** aborts within ~50ms from any application.

## Build from source

Requirements: macOS 13.0+, Swift 5.9+ (Xcode 15 or later command-line tools).

```bash
# Standalone Swift Package build (no .app bundle, no install)
swift build -c release
.build/release/Autotyper

# Full app bundle install to ~/Applications
./scripts/build_app.sh                    # release build
./scripts/build_app.sh --debug            # debug build
./scripts/build_app.sh --launch           # build, install, and open

# Stable code-signing identity (one-time, optional but strongly recommended;
# without it, every rebuild resets the Accessibility grant)
./scripts/setup_dev_cert.sh
```

The build script handles icon generation (uses the bundled `Sources/Autotyper/Resources/AppLogo.png` by default, or auto-trims transparent borders of a custom PNG when `ICON_SRC=/path/to/master.png` is set; scales to all macOS iconset sizes; builds the `.icns`), assembles the `.app` bundle with `Info.plist`, codesigns with the persistent self-signed cert when present (falls back to ad-hoc), and re-registers the bundle with LaunchServices.

## Acknowledgments

Calibration draws on published typing-behavior research and writing-process keystroke-log studies:

1. **Dhakal, V., Feit, A. M., Kristensson, P. O., & Oulasvirta, A.** (2018). *Observations on Typing from 136 Million Keystrokes.* CHI 2018.  
   [Paper](https://userinterfaces.aalto.fi/136Mkeystrokes/) · [DOI](https://doi.org/10.1145/3173574.3174220)  
   Source of bigram timing distributions, profile-baseline WPM calibration, error-rate baselines, and within-word IKI burst characteristics.

2. **Crump, M. J. C., & Logan, G. D.** (2010). *Hierarchical control and skilled typing: Evidence for word-level control over the execution of individual keystrokes.* Journal of Experimental Psychology: Learning, Memory, and Cognition, 36(6), 1369–1380.  
   [DOI](https://doi.org/10.1037/a0020696)  
   Basis for end-of-word motor rolloff and word-onset pre-loading.

3. **Inputlog research consortium** (Van Waes, Leijten, Conijn, et al.). Long-running keystroke-logging research producing distributional data on typo type frequencies, recognition latencies, and pause structures in real composition.  
   [Inputlog project](https://www.inputlog.net/)

4. **Crossley, S. A., et al.** Writing-process feature research from the Educational Data Mining community on the linearity gap between authentic and transcribed writing, informing the mid-draft cursor-jump probabilities and the leading-edge-vs-non-leading-edge insertion ratios.  
   [EDM 2024 proceedings](https://educationaldatamining.org/edm2024/)

5. **Composition-rate research.** The ~19 WPM net composition rate (typing time + thinking time + breaks, integrated across a multi-paragraph drafting session) is a robust constant across multiple decades of writing-process studies.

The Aalto 136M-keystroke corpus in particular is the largest publicly available source of human typing data and underlies most of the per-keystroke timing model. We thank the Aalto User Interfaces group for releasing it.

### Built on

- **Swift** and the **Apple frameworks** that ship with macOS:
  - SwiftUI, AppKit (UI), Combine
  - CoreGraphics (CGEvent for keystroke synthesis)
  - ApplicationServices (Accessibility / TCC)
  - Charts (post-session WPM graph, macOS 13+)
  - ImageIO and CoreImage (icon trimming, runtime image rendering)
  - Foundation, Dispatch
  - Infinitum
- **Swift Package Manager** for the build system.
- **iconutil** and **codesign** (Apple developer tools) for app packaging.
- **OpenSSL** / **LibreSSL** for the self-signed code-signing cert generation step.

No third-party Swift packages are consumed at compile time. The dependency graph is the macOS SDK and nothing else.

## Contributing

To report bugs and suggest features, use the [issue tracker][issues]. If
you have code to contribute, open a pull request. Small, focused changes
are easier to review and land. See [CONTRIBUTING.md](CONTRIBUTING.md) for
a few conventions.

## License

Copyright © TeXtUtility contributors. Distributed under the MIT License.
See [LICENSE](LICENSE) for the full text.

[issues]: https://github.com/TeXtUtility/TeXtUtility/issues
