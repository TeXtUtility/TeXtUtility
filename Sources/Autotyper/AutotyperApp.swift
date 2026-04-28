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
/// status item and refreshes whenever PlanState publishes — so progress percentage
/// updates live as the executor advances.
struct MenuBarIconView: View {
    @EnvironmentObject var state: PlanState
    @State private var checkmarkOpacity: Double = 1.0
    @State private var lastFlashedCompletion: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            iconLayer
            if state.hasUnclaimedCompletion {
                // Don't render extra text — the checkmark icon stands alone.
                EmptyView()
            } else if state.pauseRemainingMs > 0 {
                Text(pauseText)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
            } else if state.isRunning && state.totalChars > 0 {
                Text(percentText)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
            }
        }
        .onChange(of: state.hasUnclaimedCompletion) { newValue in
            if newValue && !lastFlashedCompletion {
                lastFlashedCompletion = true
                runCompletionFlash()
            } else if !newValue {
                // Reset for the next session.
                lastFlashedCompletion = false
                checkmarkOpacity = 1.0
            }
        }
    }

    /// Three blinks then solid. Pattern: visible, hidden, visible, hidden,
    /// visible, hidden, visible — three full off→on cycles ending solid.
    private func runCompletionFlash() {
        let pattern: [Double] = [1.0, 0.0, 1.0, 0.0, 1.0, 0.0, 1.0]
        let interval: Double = 0.16
        checkmarkOpacity = 1.0
        for (i, val) in pattern.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(i)) {
                withAnimation(.easeInOut(duration: interval * 0.7)) {
                    checkmarkOpacity = val
                }
            }
        }
    }

    private var percentText: String {
        let pct = Int((state.progress * 100).rounded())
        return "\(min(pct, 100))%"
    }

    private var pauseText: String {
        let total = Int(ceil(state.pauseRemainingMs / 1000.0))
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
                    .opacity(checkmarkOpacity)
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
