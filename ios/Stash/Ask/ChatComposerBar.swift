import SwiftUI

/// TextField + send, in the web's round-button convention (`StashDesign.swift`): the send circle
/// is violet-filled while there's something to send. Pure input collection — routing
/// (`store.send`, chip/gate handling) lives in `AskView`; this view only reports a tap.
///
/// A mic button (live dictation via `DictationController`) sat between the field and the send
/// circle until 2026-09-07 — removed at Will's request; voice capture stays on the Add tab's
/// voice memo. `NSSpeechRecognitionUsageDescription` left `project.yml` with it.
struct ChatComposerBar: View {
    @Binding var text: String
    let isSending: Bool
    let onSend: () -> Void

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var body: some View {
        // `.top`, not `.bottom`: the field grows to four lines, and the send circle should stay
        // on the first line rather than ride down with the last one (Will, 2026-09-07).
        HStack(alignment: .top, spacing: 8) {
            // Same face as the thread's bubbles (`StashType.body()`, DESIGN.md's one UI family) —
            // a bare `TextField` fell back to SF while the replies rendered Neue Montreal.
            TextField("Ask, or paste a link / 'remember:' to save", text: $text, axis: .vertical)
                .font(StashType.body())
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(StashColor.hairline, lineWidth: 1))
                .accessibilityIdentifier("ask.input")

            sendButton
        }
    }

    private var sendButton: some View {
        Button(action: onSend) {
            CircleSubmitIcon(size: 40, hot: canSend, busy: isSending)
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .accessibilityIdentifier("ask.send")
    }
}
