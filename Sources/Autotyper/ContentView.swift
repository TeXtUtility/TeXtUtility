import SwiftUI
import Charts
import AppKit

struct ContentView: View {
    @EnvironmentObject var state: PlanState
    @State private var hasAccessibility = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            PasteEditor(text: $state.pastedText)
                .frame(minHeight: 240)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            profileRow
            essayModeRow
            statusRow
            actionRow
            footnote
            if state.showStatsPanel {
                Divider().padding(.vertical, 4)
                SessionStatsView()
            }
        }
        .padding(16)
        .frame(width: 480)
        .onAppear {
            // Reactivate so the popover takes keyboard focus reliably.
            NSApplication.shared.activate(ignoringOtherApps: true)
            // Just refresh — never re-prompt here. The first-launch prompt
            // happens once in AppDelegate; afterwards the user uses the
            // Open Settings button.
            refreshAccessibilityStatus()
            // If a session completed since the popover was last open, claim
            // it now: clear the input field and reveal the stats panel
            // beneath. Cleared when the user starts the next session.
            if state.hasUnclaimedCompletion {
                state.hasUnclaimedCompletion = false
                state.pastedText = ""
                state.showStatsPanel = true
            }
        }
    }

    private var header: some View {
        HStack {
            appLogo
            Text("TeXtUtility").font(.headline)
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(hasAccessibility ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(hasAccessibility ? "Accessibility OK" : "Accessibility needed")
                    .font(.caption)
                if !hasAccessibility {
                    Button("Open Settings") { openAccessibilitySettings() }
                        .controlSize(.small)
                    Button("Recheck") { refreshAccessibilityStatus() }
                        .controlSize(.small)
                }
            }
        }
    }

    /// Recheck just refreshes the trust state — never re-opens the system
    /// prompt. Re-prompting on every click is what made the dialog appear
    /// "stuck open" to the user when an underlying signing issue was keeping
    /// AXIsProcessTrusted() at false.
    private func refreshAccessibilityStatus() {
        hasAccessibility = AccessibilityCheck.isTrusted()
        if hasAccessibility {
            _ = SafetyController.shared.installTap()
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private var profileRow: some View {
        HStack(spacing: 8) {
            Text("Profile").foregroundStyle(.secondary).font(.caption)
            Picker("", selection: $state.selectedProfile) {
                ForEach(ProfileKind.allCases) { kind in
                    Text("\(kind.displayName) — \(Int(kind.targetWpm)) WPM")
                        .tag(kind)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            Spacer()
        }
    }

    private var essayModeRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Toggle(isOn: $state.essayMode) {
                    Text("Essay mode (anti-Writing-Replay)")
                        .font(.caption)
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)
                Spacer()
            }
            if state.essayMode {
                Text("Mid-draft jumps · Late-pass edits · Multi-min breaks · ~7 min/100 words")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            if state.isPaused {
                Image(systemName: "pause.circle.fill")
                    .foregroundStyle(.blue)
                Text("Paused")
                    .font(.caption)
                    .foregroundStyle(.blue)
            } else if state.pauseRemainingMs > 0 {
                Image(systemName: "pause.circle.fill")
                    .foregroundStyle(.orange)
                Text("On break: \(formatPause(state.pauseRemainingMs))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.orange)
            } else {
                Text(state.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            if state.showStatsPanel {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if state.totalChars > 0 {
                let pct = Int((state.progress * 100).rounded())
                Text("\(min(pct, 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatPause(_ ms: Double) -> String {
        let totalSec = max(0, ms) / 1000.0
        if totalSec < 60 {
            return String(format: "%.0fs", ceil(totalSec))
        }
        let total = Int(ceil(totalSec))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button(action: startTyping) {
                Text(startButtonLabel)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(state.isRunning || state.pastedText.isEmpty || !hasAccessibility)

            Button(state.isPaused ? "Resume" : "Pause") { state.togglePause() }
                .keyboardShortcut("p", modifiers: [.command])
                .controlSize(.large)
                .disabled(!state.isRunning || state.countdownSeconds > 0)

            Button("Stop") { state.requestAbort() }
                .keyboardShortcut(".", modifiers: [.command])
                .controlSize(.large)
                .disabled(!state.isRunning)
        }
    }

    private var footnote: some View {
        HStack {
            Text("Pause: ⌘P")
            Text("·")
            Text("Stop: ⌘.")
            Text("·")
            Text("Panic: ⌥⌘. (global)")
            Spacer()
            Text("Quit: ⌘Q")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private var appLogo: some View {
        if let url = Bundle.module.url(forResource: "AppLogo", withExtension: "png"),
           let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: "keyboard")
                .foregroundStyle(.secondary)
        }
    }

    private var startButtonLabel: String {
        if state.isRunning && state.countdownSeconds > 0 { return "Starting in \(state.countdownSeconds)…" }
        if state.isRunning { return "Typing…" }
        return "Start typing in 3 s"
    }

    private func startTyping() {
        state.resetForRun()
        state.isRunning = true
        state.countdownSeconds = 3
        state.statusMessage = "Focus your target window…"

        Task { @MainActor in
            for s in stride(from: 3, through: 1, by: -1) {
                state.countdownSeconds = s
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            state.countdownSeconds = 0

            // Capture target PID at the moment typing begins — whatever app is
            // frontmost now is the target. Events will be posted to this PID
            // for the entire session, so the user can switch focus elsewhere
            // without redirecting our typing.
            let myPid = ProcessInfo.processInfo.processIdentifier
            if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != myPid {
                state.targetPid = app.processIdentifier
                state.targetAppName = app.localizedName ?? "target"
            } else {
                state.statusMessage = "Error: focus the target window during the 3-second countdown"
                state.isRunning = false
                return
            }
            state.statusMessage = "Typing"

            let weakState = state
            SafetyController.shared.startTypingSession(
                onAbort: { reason in
                    Task { @MainActor in
                        weakState.requestAbort()
                        weakState.statusMessage = "Aborted: \(reason)"
                    }
                },
                onPauseToggle: {
                    Task { @MainActor in
                        weakState.togglePause()
                    }
                }
            )
            defer { SafetyController.shared.endTypingSession() }

            let profile = ProfileParams.from(state.selectedProfile)
            let sampler = Sampler(seed: nil)
            let plan = Planner.plan(
                text: state.pastedText,
                profile: profile,
                essayMode: state.essayMode,
                sampler: sampler
            )
            // Count tap events (the only ones that increment progress).
            // Essay-mode plans have 3-5× more events than input chars due to
            // typo corrections, mid-draft jumps, and revision passes.
            state.totalChars = plan.reduce(0) { acc, ev in
                if case .tap = ev.action { return acc + 1 }
                return acc
            }
            await Executor.runPlan(plan, state: state)

            state.isRunning = false
            if !state.abortFlag {
                state.statusMessage = "Done"
                state.hasUnclaimedCompletion = true
            }
        }
    }
}

/// Post-session stats panel shown beneath the main controls after the popover
/// is reopened on a completed run. Cleared the next time the user hits Start.
struct SessionStatsView: View {
    @EnvironmentObject var state: PlanState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last session")
                .font(.headline)
            HStack(alignment: .top, spacing: 22) {
                statBlock(label: "Time", value: formatDuration(state.sessionDurationMs))
                statBlock(label: "Words", value: "\(state.sessionCharsCommitted / 5)")
                statBlock(label: "Chars", value: "\(state.sessionCharsCommitted)")
                statBlock(label: "Deletions", value: "\(state.sessionDeletions)")
                statBlock(label: "Edits", value: "\(state.sessionEdits)")
                statBlock(label: "Avg WPM", value: avgWpmText)
            }
            chart
        }
    }

    @ViewBuilder
    private var chart: some View {
        if state.sessionWpmSamples.count >= 2 {
            Chart(state.sessionWpmSamples) { sample in
                LineMark(
                    x: .value("t", sample.elapsed),
                    y: .value("WPM", sample.wpm)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(.blue)
            }
            .chartXAxisLabel("seconds")
            .chartYAxisLabel("WPM")
            .frame(height: 140)
        } else {
            Text("Not enough samples for a graph.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(height: 60, alignment: .center)
                .frame(maxWidth: .infinity)
        }
    }

    private func statBlock(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit())
        }
    }

    private func formatDuration(_ ms: Double) -> String {
        let total = Int(ms / 1000)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%dh %02dm", h, m) }
        return String(format: "%dm %02ds", m, s)
    }

    private var avgWpmText: String {
        guard !state.sessionWpmSamples.isEmpty else { return "—" }
        let avg = state.sessionWpmSamples.map(\.wpm).reduce(0, +) / Double(state.sessionWpmSamples.count)
        return String(format: "%.0f", avg)
    }
}
