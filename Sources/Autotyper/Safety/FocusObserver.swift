import AppKit
import Foundation

/// Watches for frontmost-app changes via NSWorkspace notifications. If the user
/// switches away (Spotlight, ⌘-Tab, notification click), we abort to prevent typing
/// into the wrong window.
@MainActor
final class FocusObserver {
    private var observer: NSObjectProtocol?
    private var baselineBundleId: String?
    private var onChange: (() -> Void)?

    func start(onChange: @escaping () -> Void) {
        self.onChange = onChange
        baselineBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            // The notification was posted with queue: .main so this is genuinely the
            // main thread; assumeIsolated lets us reach the main-actor properties.
            MainActor.assumeIsolated {
                guard let self else { return }
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let newId = app?.bundleIdentifier
                if newId != self.baselineBundleId {
                    self.onChange?()
                }
            }
        }
    }

    func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
        baselineBundleId = nil
        onChange = nil
    }
}
