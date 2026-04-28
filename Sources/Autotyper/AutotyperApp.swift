import SwiftUI
import AppKit

@main
struct AutotyperApp: App {
    /// One PlanState lives at App scope so both the menu-bar icon view and the
    /// popover ContentView observe the same instance. State persists across
    /// popover open/close.
    @StateObject private var state = PlanState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(state)
        } label: {
            MenuBarIconView()
                .environmentObject(state)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar app: no Dock icon. The popover gets key-window focus when shown.
        NSApplication.shared.setActivationPolicy(.accessory)
        _ = SafetyController.shared.installTap()
        // Bootstrap the Accessibility flow once per app launch — adds the app
        // to System Settings → Accessibility and shows the system dialog. We
        // never re-prompt from the popover; the user uses Open Settings /
        // Recheck buttons after the initial nudge.
        if !AccessibilityCheck.isTrusted() {
            _ = AccessibilityCheck.promptForAccess()
        }
    }
}

/// Custom SwiftUI menu-bar icon. The HStack is rendered into an NSImage for the
/// status item and refreshes whenever PlanState publishes, so progress percentage
/// updates live as the executor advances.
struct MenuBarIconView: View {
    @EnvironmentObject var state: PlanState

    var body: some View {
        HStack(spacing: 4) {
            iconLayer
            if state.hasUnclaimedCompletion {
                // Don't render extra text, the checkmark icon stands alone.
                EmptyView()
            } else if state.isPaused {
                Text("⏸")
                    .font(.system(size: 11, weight: .semibold))
            } else if state.pauseRemainingMs > 0 {
                Text(pauseText)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
            } else if state.isRunning && state.totalChars > 0 {
                Text(percentText)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
            }
        }
        .onChange(of: state.hasUnclaimedCompletion) { newValue in
            if newValue {
                Task { @MainActor in await runCompletionFlash() }
            } else {
                state.checkmarkVisible = true
            }
        }
    }

    /// Three blinks then solid. Driven from a single MainActor Task so SwiftUI
    /// can't coalesce the writes — each write awaits a sleep before the next,
    /// guaranteeing the NSImage rasterization for MenuBarExtra picks up
    /// every step.
    @MainActor
    private func runCompletionFlash() async {
        let pattern: [Bool] = [false, true, false, true, false, true]
        let stepNs: UInt64 = 240_000_000   // 0.24 s
        for visible in pattern {
            try? await Task.sleep(nanoseconds: stepNs)
            // Bail out if the user reopened the popover and claimed completion
            // mid-flash — leave the checkmark solid.
            if !state.hasUnclaimedCompletion {
                state.checkmarkVisible = true
                return
            }
            state.checkmarkVisible = visible
        }
        state.checkmarkVisible = true
    }

    private var percentText: String {
        let pct = Int((state.progress * 100).rounded())
        return "\(min(pct, 100))%"
    }

    private var pauseText: String {
        let totalSec = max(0, state.pauseRemainingMs) / 1000.0
        if totalSec < 60 {
            return String(format: "%.0fs", ceil(totalSec))
        }
        let total = Int(ceil(totalSec))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    @ViewBuilder
    private var iconLayer: some View {
        ZStack {
            if state.hasUnclaimedCompletion {
                Image(systemName: "checkmark.circle.fill")
                    .imageScale(.medium)
                    .foregroundStyle(.white)
                    .opacity(state.checkmarkVisible ? 1 : 0)
            } else if state.isPaused {
                Image(systemName: "pause.circle.fill")
                    .imageScale(.medium)
            } else if state.pauseRemainingMs > 0 {
                Image(systemName: "pause.circle")
                    .imageScale(.medium)
            } else if state.isRunning {
                Circle()
                    .trim(from: 0, to: max(0.001, state.progress))
                    .stroke(.primary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 16, height: 16)
                Image(systemName: "keyboard.fill")
                    .imageScale(.medium)
            } else {
                Image(systemName: "keyboard")
                    .imageScale(.medium)
            }
        }
        .frame(width: 18, height: 18)
    }
}
