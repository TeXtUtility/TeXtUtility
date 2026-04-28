import SwiftUI

/// One sample of WPM measured in a rolling window during a typing session.
struct WpmSample: Identifiable {
    let id = UUID()
    let elapsed: TimeInterval   // seconds since session start
    let wpm: Double
}

@MainActor
final class PlanState: ObservableObject {
    @Published var pastedText: String = ""
    @Published var selectedProfile: ProfileKind = .medium
    @Published var essayMode: Bool = true   // anti-Writing-Replay countermeasures on
    @Published var isRunning: Bool = false
    @Published var countdownSeconds: Int = 0
    @Published var progress: Double = 0
    @Published var statusMessage: String = "Ready"
    @Published var charsTyped: Int = 0
    @Published var totalChars: Int = 0
    /// Captured at end of countdown — the PID of the frontmost app at that
    /// moment. Events are posted directly to this PID via CGEventPostToPid so
    /// the user can switch focus elsewhere without redirecting our typing.
    @Published var targetPid: pid_t = 0
    @Published var targetAppName: String = ""
    /// > 0 while the executor is in a long pause. UI binds this for countdown.
    @Published var pauseRemainingMs: Double = 0

    /// True from the moment a session finishes successfully until the user
    /// next reopens the popover. Drives the menu-bar checkmark and the
    /// post-session stats panel.
    @Published var hasUnclaimedCompletion: Bool = false
    /// True when the post-session stats panel should be shown (set when the
    /// popover opens after an unclaimed completion; cleared on next Start).
    @Published var showStatsPanel: Bool = false

    // Session stats — populated by the Executor during a run, read by the
    // stats panel after completion.
    @Published var sessionWpmSamples: [WpmSample] = []
    @Published var sessionDurationMs: Double = 0
    @Published var sessionInputChars: Int = 0   // chars in source text
    @Published var sessionInputWords: Int = 0   // words in source text
    @Published var sessionCharsCommitted: Int = 0   // .char events emitted
    @Published var sessionDeletions: Int = 0    // backspace events emitted
    /// "Edits" = backspace bursts of ≥2 (typo corrections + mid-draft jumps).
    /// A single trailing-char autocorrect counts as 0 edits; a deliberate
    /// word-replacement counts as 1.
    @Published var sessionEdits: Int = 0

    private(set) var abortFlag: Bool = false

    func requestAbort() { abortFlag = true }

    func resetForRun() {
        abortFlag = false
        progress = 0
        charsTyped = 0
        totalChars = 0
        pauseRemainingMs = 0
        targetPid = 0
        targetAppName = ""
        hasUnclaimedCompletion = false
        showStatsPanel = false
        sessionWpmSamples = []
        sessionDurationMs = 0
        sessionInputChars = 0
        sessionInputWords = 0
        sessionCharsCommitted = 0
        sessionDeletions = 0
        sessionEdits = 0
    }
}

/// Eight profiles spanning the realistic WPM spectrum from Aalto's 136M-keystroke
/// dataset (CHI 2018). Names map to typist personas; numbers are calibrated against
/// research-reported means so each profile feels distinct in both speed and texture.
enum ProfileKind: String, CaseIterable, Identifiable {
    case huntPeck     // beginner, looks at keyboard, lots of corrections
    case thoughtful   // deliberate composer, slow, lots of vocabulary second-guessing
    case casual       // average adult typist
    case medium       // standard touch typist (default)
    case office       // programmer / office worker, fluent and accurate
    case fluent       // confident touch typist
    case fast         // skilled, quick
    case touchTypist  // expert, near-flawless

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .huntPeck:    return "Hunt-Peck"
        case .thoughtful:  return "Thoughtful"
        case .casual:      return "Casual"
        case .medium:      return "Medium"
        case .office:      return "Office"
        case .fluent:      return "Fluent"
        case .fast:        return "Fast"
        case .touchTypist: return "Touch-Typist"
        }
    }

    /// Target words-per-minute. From Aalto research: 22 WPM = beginner hunt-peck,
    /// 40 WPM = adult population mean, 53 WPM = programmer cohort, 80+ WPM = expert,
    /// 95 WPM ~ top-decile touch typist.
    var targetWpm: Double {
        switch self {
        case .huntPeck:    return 22
        case .thoughtful:  return 35
        case .casual:      return 45
        case .medium:      return 55
        case .office:      return 65
        case .fluent:      return 75
        case .fast:        return 85
        case .touchTypist: return 95
        }
    }

    /// One-line summary shown under each profile in the picker.
    var summary: String {
        switch self {
        case .huntPeck:    return "Beginner, lots of pauses and errors"
        case .thoughtful:  return "Deliberate composer, vocabulary second-guessing"
        case .casual:      return "Average adult typist"
        case .medium:      return "Standard touch typist (default)"
        case .office:      return "Programmer, fluent and accurate"
        case .fluent:      return "Confident touch typist"
        case .fast:        return "Skilled, quick, low-error"
        case .touchTypist: return "Expert, near-flawless"
        }
    }

    /// Mean inter-keystroke interval in ms (60_000 / (WPM × 5)).
    var baseIkiMs: Double { 60_000.0 / (targetWpm * 5.0) }
}
