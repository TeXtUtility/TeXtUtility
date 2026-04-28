import CoreGraphics
import Foundation

enum Executor {
    /// Phase 1 fallback path: constant inter-key delay, no variance, no PID
    /// targeting. Kept as a smoke-test entry point.
    @MainActor
    static func runConstantSpeed(text: String, ikiMs: Double, state: PlanState) async {
        let source = CGEventSource(stateID: .combinedSessionState)
        let location = CGEventTapLocation.cghidEventTap
        let dwellMs: Double = 75
        let perKeyMs = max(ikiMs, dwellMs + 5)
        let postKeyPauseMs = perKeyMs - dwellMs

        defer { ModifierGuard.flushAllModifiers(source: source, location: location) }

        for (i, ch) in text.enumerated() {
            if state.abortFlag { break }
            guard let (code, needsShift) = KeycodeMap.keycode(for: ch) else { continue }
            let mods: CGEventFlags = needsShift ? [.maskShift] : []
            await emitTap(source: source, location: location, code: code, modifiers: mods, dwellMs: dwellMs, targetPid: 0)
            state.charsTyped = i + 1
            state.progress = Double(i + 1) / Double(max(state.totalChars, 1))
            if postKeyPauseMs > 0 {
                try? await Task.sleep(nanoseconds: UInt64(postKeyPauseMs * 1_000_000))
            }
        }
    }

    /// Walk a pre-computed [KeyEvent] plan from the Planner. Honors `delayBeforeMs`
    /// for IKI/boundary pauses and `dwellMs` for key-down hold.
    ///
    /// If `state.targetPid > 0`, events are posted via CGEventPostToPid directly
    /// to the target process, bypassing the focused-app routing of the HID tap.
    /// This lets the user switch focus to other apps mid-typing without
    /// redirecting keystrokes.
    @MainActor
    static func runPlan(_ plan: [KeyEvent], state: PlanState) async {
        let source = CGEventSource(stateID: .combinedSessionState)
        let location = CGEventTapLocation.cghidEventTap
        let targetPid = state.targetPid
        let backspaceCode = Planner.backspaceKeycode

        defer { ModifierGuard.flushAllModifiers(source: source, location: location) }

        let sessionStart = Date()
        // Rolling-window WPM: characters emitted in the trailing 5 s, scaled to
        // a per-minute words rate (chars / 5).
        let windowSeconds: TimeInterval = 5
        var windowEvents: [TimeInterval] = []   // timestamps of recent .char taps
        var lastSampleAt: TimeInterval = 0
        var charsCommitted = 0
        var deletions = 0
        var edits = 0
        var currentBackspaceRun = 0
        // Total ms paused so the WPM rolling window discounts time spent
        // user-paused (otherwise WPM looks artificially low after a long pause).
        var pausedMsTotal: Double = 0

        var charIndex = 0
        for event in plan {
            if state.abortFlag { break }
            // If user paused mid-stream, stall here BEFORE consuming this
            // event's IKI so we don't extend the inter-keystroke gap by the
            // pause length.
            pausedMsTotal += await waitWhilePaused(state: state)
            if state.abortFlag { break }
            await sleepWithAbortCheck(ms: event.delayBeforeMs, pauseMs: event.pauseMs, state: state)
            if state.abortFlag { break }
            pausedMsTotal += await waitWhilePaused(state: state)
            if state.abortFlag { break }

            switch event.action {
            case .tap(let code, let mods):
                await emitTap(source: source, location: location, code: code, modifiers: mods, dwellMs: event.dwellMs, targetPid: targetPid)
                charIndex += 1
                state.charsTyped = charIndex
                if state.totalChars > 0 {
                    state.progress = Double(charIndex) / Double(state.totalChars)
                }

                // Stats: classify the tap. Backspaces with no shift / option /
                // command are deletions; everything else (with no command-arrow
                // / option-arrow modifier) we count as a committed character.
                let isBackspace = code == backspaceCode && mods.isEmpty
                let isNavOrCommand = mods.contains(.maskCommand) || mods.contains(.maskAlternate)

                if isBackspace {
                    deletions += 1
                    currentBackspaceRun += 1
                } else if isNavOrCommand {
                    // Navigation / find — not a character commit, not a deletion.
                    if currentBackspaceRun >= 2 { edits += 1 }
                    currentBackspaceRun = 0
                } else {
                    if currentBackspaceRun >= 2 { edits += 1 }
                    currentBackspaceRun = 0
                    charsCommitted += 1
                    let now = Date().timeIntervalSince(sessionStart) - pausedMsTotal / 1000.0
                    windowEvents.append(now)
                    while let first = windowEvents.first, now - first > windowSeconds {
                        windowEvents.removeFirst()
                    }
                    if now - lastSampleAt >= 1.0 || lastSampleAt == 0 {
                        let actualSpan = max(0.5, min(windowSeconds, now))
                        let wpm = (Double(windowEvents.count) / 5.0) * (60.0 / actualSpan)
                        state.sessionWpmSamples.append(WpmSample(elapsed: now, wpm: wpm))
                        state.sessionCharsCommitted = charsCommitted
                        state.sessionDeletions = deletions
                        state.sessionEdits = edits
                        lastSampleAt = now
                    }
                }
            case .keyDown(let code, let mods):
                emitDown(source: source, location: location, code: code, modifiers: mods, targetPid: targetPid)
            case .keyUp(let code, let mods):
                emitUp(source: source, location: location, code: code, modifiers: mods, targetPid: targetPid)
            }
        }
        if currentBackspaceRun >= 2 { edits += 1 }
        state.sessionCharsCommitted = charsCommitted
        state.sessionDeletions = deletions
        state.sessionEdits = edits
        state.sessionDurationMs = Date().timeIntervalSince(sessionStart) * 1000 - pausedMsTotal
    }

    /// Sleep for `ms` total in 250 ms slices. The `pauseMs` portion (sentence
    /// boundary, paragraph break, review pause, session break, etc.) is shown
    /// to the user as a live countdown via `state.pauseRemainingMs`. Pure
    /// typing-IKI delays (pauseMs == 0) tick down silently. Honors
    /// `state.isPaused` by stalling without decrementing remaining time.
    @MainActor
    private static func sleepWithAbortCheck(ms: Double, pauseMs: Double, state: PlanState) async {
        guard ms > 0 else { return }
        // We want pauseRemainingMs to reflect the FULL gap before the next
        // keystroke whenever the gap is dominated by an explicit pause —
        // from the user's perspective the cursor sits idle for `ms` ms total,
        // so showing `ms` reads honestly. A small lower bound on `pauseMs`
        // prevents tiny incidentals (sub-250 ms between-burst gaps, very
        // short comma pauses) from flickering the menu-bar icon between
        // progress and pause states. Every example the user named (between
        // sentences, between paragraphs, review pauses, session breaks)
        // clears this threshold easily.
        let showCountdown = pauseMs >= 250
        if showCountdown {
            state.pauseRemainingMs = ms
        }
        let sliceMs: Double = 250
        var remaining = ms
        while remaining > 0 {
            if state.abortFlag {
                state.pauseRemainingMs = 0
                return
            }
            // User-paused: stall here, holding `pauseRemainingMs` steady.
            while state.isPaused && !state.abortFlag {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            if state.abortFlag {
                state.pauseRemainingMs = 0
                return
            }
            let chunk = min(remaining, sliceMs)
            try? await Task.sleep(nanoseconds: UInt64(chunk * 1_000_000))
            remaining -= chunk
            if showCountdown {
                state.pauseRemainingMs = max(0, remaining)
            }
        }
        if showCountdown {
            state.pauseRemainingMs = 0
        }
    }

    /// Stall while `state.isPaused` is true; returns the total ms waited.
    @MainActor
    private static func waitWhilePaused(state: PlanState) async -> Double {
        guard state.isPaused else { return 0 }
        let start = Date()
        while state.isPaused && !state.abortFlag {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return Date().timeIntervalSince(start) * 1000
    }

    @MainActor
    private static func emitTap(
        source: CGEventSource?,
        location: CGEventTapLocation,
        code: CGKeyCode,
        modifiers: CGEventFlags,
        dwellMs: Double,
        targetPid: pid_t
    ) async {
        emitDown(source: source, location: location, code: code, modifiers: modifiers, targetPid: targetPid)
        try? await Task.sleep(nanoseconds: UInt64(dwellMs * 1_000_000))
        emitUp(source: source, location: location, code: code, modifiers: modifiers, targetPid: targetPid)
        if modifiers.contains(.maskShift) {
            if let ev = CGEvent(keyboardEventSource: source, virtualKey: KeycodeMap.shiftKey, keyDown: false) {
                ev.flags = []
                postEvent(ev, location: location, targetPid: targetPid)
            }
        }
    }

    private static func emitDown(source: CGEventSource?, location: CGEventTapLocation, code: CGKeyCode, modifiers: CGEventFlags, targetPid: pid_t) {
        guard let ev = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true) else { return }
        ev.flags = modifiers
        postEvent(ev, location: location, targetPid: targetPid)
    }

    private static func emitUp(source: CGEventSource?, location: CGEventTapLocation, code: CGKeyCode, modifiers: CGEventFlags, targetPid: pid_t) {
        guard let ev = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { return }
        ev.flags = modifiers
        postEvent(ev, location: location, targetPid: targetPid)
    }

    /// Post via PID-target if available (events stay locked to the target app
    /// regardless of focus), else fall back to the HID tap.
    private static func postEvent(_ event: CGEvent, location: CGEventTapLocation, targetPid: pid_t) {
        if targetPid > 0 {
            event.postToPid(targetPid)
        } else {
            event.post(tap: location)
        }
    }
}
