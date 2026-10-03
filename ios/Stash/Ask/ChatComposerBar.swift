import SwiftUI

/// TextField + send, in the web's round-button convention (`StashDesign.swift`): the send circle
/// is violet-filled while there's something to send. Pure input collection — sending and the
/// subscription gate live in `AskView`; this view only reports a tap.
///
/// Placeholder "Ask your stash…" is the web mole's, verbatim (plan 15): Ask is retrieval-only on
/// every platform (`docs/ui-changes.md`, 2026-08-27), so it no longer advertises the retired
/// "paste a link / 'remember:' to save" capture routes.
///
/// A mic button (live dictation via `DictationController`) sat between the field and the send
/// circle until 2026-09-07 — removed at Will's request; voice capture stays on the Add tab's
/// voice memo. `NSSpeechRecognitionUsageDescription` left `project.yml` with it.
///
/// Plan 16 (task 2d, accessibility): the field is the `reading` role (17 pt at the default size, the
/// bubbles' face and size); its placeholder is `muted` (5.38:1 — the system's placeholder grey was
/// 1.73); a tap anywhere on the pill focuses it, its padding included (the field's own frame is just
/// its text line); and the send circle is named for VoiceOver.
struct ChatComposerBar: View {
    @Binding var text: String
    /// Owned by `AskView`, which puts the keyboard away before anything is shown over the thread
    /// and swaps its header controls for "Cancel" while this is true.
    var isFocused: FocusState<Bool>.Binding
    /// `AskView`'s VoiceOver focus: where it goes when Cancel goes, if not to the thread.
    var accessibilityFocus: AccessibilityFocusState<AskAccessibilityFocus?>.Binding
    let isSending: Bool
    let onSend: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let placeholder = "Ask your stash…"
    /// The prompt at the two largest sizes, where the whole one is cut ("Ask your stas…" at AX5). The
    /// field's VoiceOver label stays the whole one.
    private static let shortPlaceholder = "Ask…"

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var body: some View {
        // `.top`, not `.bottom`: the field grows to four lines, and the send circle should stay
        // on the first line rather than ride down with the last one (Will, 2026-09-07).
        HStack(alignment: .top, spacing: 8) {
            // Same face as the thread's bubbles (DESIGN.md's one UI family) — a bare `TextField`
            // fell back to SF while the replies rendered Neue Montreal.
            TextField(Self.placeholder, text: $text,
                      prompt: Text(dynamicTypeSize >= .accessibility4 ? Self.shortPlaceholder : Self.placeholder)
                        .foregroundStyle(StashColor.muted),
                      axis: .vertical)
                .focused(isFocused)
                .accessibilityFocused(accessibilityFocus, equals: .composer)
                .stashFont(.reading)
                .lineLimit(1...4)
                // On the field itself (its frame is its text line, as the tests measure): the pill
                // around it isn't one element.
                .accessibilityIdentifier("ask.input")
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background {
                    // The pill's padding takes the taps the field's text line doesn't, and focuses the
                    // field: the padding only (`AskPillPadding`), at least 44 pt tall (HIG) — over the
                    // field's own line too, the gesture took the field's taps on iOS 18.5 and it never
                    // focused. In front of the fill (an earlier background draws over a later one), or
                    // the fill takes the tap. Hidden from VoiceOver: the field itself is the control.
                    Color.clear
                        .frame(minHeight: 44)
                        .contentShape(AskPillPadding(horizontal: 14, vertical: 10), eoFill: true)
                        .onTapGesture { isFocused.wrappedValue = true }
                        .accessibilityHidden(true)
                }
                .background {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(.systemBackground))
                        .accessibilityHidden(true)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(StashColor.hairline, lineWidth: 1)
                        .allowsHitTesting(false)
                }

            sendButton
        }
    }

    private var sendButton: some View {
        Button(action: onSend) {
            CircleSubmitIcon(size: 40, hot: canSend, busy: isSending)
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .stashIconControl("Send", systemImage: "paperplane.fill")
        .accessibilityIdentifier("ask.send")
    }
}

/// A field's pill less the field itself (plan 16, task 2d): the ring of padding around it, as an even-odd
/// content shape, so a tap there can focus the field while a tap on the field always reaches the field.
/// (A tap gesture across the whole pill took the field's own taps on iOS 18.5, and it never focused.)
/// The hole is the shape's rect inset by the pill's padding — the field's frame, or a little more where
/// the shape is taller than the pill.
struct AskPillPadding: Shape {
    let horizontal: CGFloat
    let vertical: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRect(rect.insetBy(dx: horizontal, dy: vertical))
        return path
    }
}
