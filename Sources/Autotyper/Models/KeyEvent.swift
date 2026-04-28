import CoreGraphics

/// Single atomic action the executor will perform. Carries CGEventFlags rather than
/// a bool for shift, so navigation/edit sequences can flow through with arbitrary
/// modifiers (Option, Cmd, Shift+Option for selection, etc.).
struct KeyEvent {
    enum Action {
        case tap(code: CGKeyCode, modifiers: CGEventFlags)
        case keyDown(code: CGKeyCode, modifiers: CGEventFlags)
        case keyUp(code: CGKeyCode, modifiers: CGEventFlags)
    }

    let action: Action
    let delayBeforeMs: Double
    let dwellMs: Double
}
