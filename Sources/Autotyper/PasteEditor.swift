import SwiftUI
import AppKit

/// SwiftUI wrapper around NSTextView. Editing has to survive constant SwiftUI
/// re-renders without the wrapper clobbering cursor/selection/undo every time the
/// parent state ticks. The `lastSyncedText` sentinel lets `updateNSView` skip the
/// write whenever the binding matches what we last received from the textView —
/// i.e. when the change originated from the user typing here.
struct PasteEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        // Disable every "helpful" auto-feature that interferes with raw text input.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false

        textView.isRichText = false
        textView.usesFontPanel = false
        textView.usesFindPanel = true
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.delegate = context.coordinator

        textView.string = text
        context.coordinator.lastSyncedText = text
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // Refresh parent (carries the current Binding closure) so textDidChange
        // writes through to the latest source of truth.
        context.coordinator.parent = self
        guard let textView = nsView.documentView as? NSTextView else { return }

        // The single rule: only write to the textView if the binding has changed
        // for a reason OTHER than this textView itself reporting in. If text equals
        // what we last sent up, the textView is already authoritative — leave it.
        if text == context.coordinator.lastSyncedText { return }
        if textView.string == text {
            context.coordinator.lastSyncedText = text
            return
        }

        // External update (programmatic). Replace contents while keeping the cursor
        // somewhere sane.
        let oldRanges = textView.selectedRanges
        textView.string = text
        // Try to keep cursor at its old position, clamped to new length.
        if let firstRange = oldRanges.first {
            let r = firstRange.rangeValue
            let safeLoc = min(r.location, (text as NSString).length)
            textView.setSelectedRange(NSRange(location: safeLoc, length: 0))
        }
        context.coordinator.lastSyncedText = text
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PasteEditor
        var lastSyncedText: String = ""

        init(_ parent: PasteEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let new = tv.string
            lastSyncedText = new
            // Write through the @Binding. The parent's StateObject will republish,
            // SwiftUI will re-render, updateNSView will run — but it'll see
            // text == lastSyncedText and skip writing back. No cursor jumping.
            if parent.text != new { parent.text = new }
        }
    }
}
