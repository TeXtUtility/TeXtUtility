# Contributing

Thanks for considering a contribution to TeXtUtility. A few conventions to
keep patches easy to review:

## Quick start

```
git clone https://github.com/TeXtUtility/TeXtUtility.git
cd TeXtUtility
./scripts/setup_dev_cert.sh    # one-time, stable code-signing identity
swift build -c release          # ~30 s on first run
swift run                       # launches as a menu-bar app
./scripts/build_app.sh --launch # install to ~/Applications/TeXtUtility.app
```

The `setup_dev_cert.sh` step is recommended on a working machine. macOS
keys the Accessibility grant by the binary's "designated requirement,"
which drifts on every ad-hoc rebuild — having a stable self-signed
identity means you grant Accessibility once, not every time you rebuild.

## Code style

- Swift 5.9, targeting macOS 13+. Most state is `@MainActor`-isolated
  since the app is GUI-bound; preserve that.
- The typing engine lives under `Sources/Autotyper/Engine/` and is
  pure-data: text in, `[KeyEvent]` out, no AppKit / SwiftUI imports.
  Keep it that way — UI concerns belong in `ContentView.swift` /
  `AutotyperApp.swift`, executor concerns in `Sources/Autotyper/Executor/`.
- Each engine layer (`Planner`, `TypoInjector`, `MidDraftReviser`,
  `SessionPacer`, `DurationTargeter`, `FatigueModel`, `WpmSmoother`,
  etc.) does one thing and operates on the shared `[LogicalKey]` /
  `[KeyEvent]` types in `Sources/Autotyper/Models/`. New behavior should
  follow that shape rather than reaching across layers.
- Calibration choices (timing constants, error-rate ranges, pause
  distributions) should cite their source in a comment. The README
  bibliography lists the corpora and papers we draw on; if you add a
  new effect, add the citation alongside.

## Testing

There's no formal test target yet. For pure-engine math (smoothing,
fatigue ramps, bigram tables, etc.) the working pattern is a small
standalone script in `/tmp` that copies the function under test, feeds
it synthetic inputs, and asserts the output — see the `WpmSmoother`
validation that shipped with that change for an example. If you add
non-trivial math, please include a similar check in the PR description
so reviewers can repro it.

For UI / executor changes, please describe how you exercised the path
(profile chosen, text length, target app, observed behavior).

## Pull requests

- One concern per PR. Small and focused beats large and sweeping.
- Run `swift build -c release` before opening; the release build is
  what ships and surfaces warnings the debug build hides.
- If the change touches the build script, the install path, the bundle
  id, or the code-signing flow, please flag it in the PR description so
  reviewers can spot TCC-grant implications.

## Reporting bugs

When opening an issue, please include:

- macOS version (`sw_vers`).
- The output of `codesign -dvv ~/Applications/TeXtUtility.app` if the
  bug is install / permission related.
- Whether the bug reproduces with `swift run` or only with the
  installed `.app`.
- For typing-fidelity reports, the source text length, the chosen
  profile, whether essay mode was on, and (if possible) the target app
  and a description of the observed vs. expected behavior.
