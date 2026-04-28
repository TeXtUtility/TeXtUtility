import CoreGraphics

/// Single atomic action the executor will perform. Carries CGEventFlags rather than
/// a bool for shift, so navigation/edit sequences can flow through with arbitrary
/// modifiers (Option, Cmd, Shift+Option for selection, etc.).
///
/// `pauseMs` is the portion of `delayBeforeMs` that's an explicit pause (sentence
/// boundary, paragraph break, review pause, word-onset hesitation, session break,
/// mid-draft jump pause, accumulated extraDelay). The remainder is typing rhythm
/// (the per-key inter-keystroke interval). The Executor uses `pauseMs` to drive
/// the menu-bar countdown so the user sees every pause, not just multi-minute
/// session breaks.
struct KeyEvent {
    enum Action {
        case tap(code: CGKeyCode, modifiers: CGEventFlags)
        case keyDown(code: CGKeyCode, modifiers: CGEventFlags)
        case keyUp(code: CGKeyCode, modifiers: CGEventFlags)
    }

    let action: Action
    let delayBeforeMs: Double
    let pauseMs: Double
    let dwellMs: Double

    init(action: Action, delayBeforeMs: Double, pauseMs: Double = 0, dwellMs: Double) {
        self.action = action
        self.delayBeforeMs = delayBeforeMs
        self.pauseMs = pauseMs
        self.dwellMs = dwellMs
    }
}
