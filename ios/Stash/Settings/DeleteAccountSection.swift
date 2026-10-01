import SwiftUI
import StashKit

/// Settings, after Sign Out (5.1.1(v)): a destructive "Delete account" row → a sheet whose
/// consequence copy mirrors `src/components/settings/DeleteAccountSection.tsx` almost verbatim
/// ("Permanently deletes your account and everything in it: every item, file, transcript, note,
/// and conversation. Your phone number is unlinked and any subscription is canceled. This cannot
/// be undone.") with the same type-to-confirm gate: the destructive "Delete everything" button is
/// enabled ONLY on an exact `"DELETE"` match, never a case-insensitive or trimmed one — same as
/// web's `confirmation !== CONFIRM_WORD` check.
///
/// Plan 14 fix wave B (finding #7, product bug from task-5-report.md): this row used to own the
/// sheet's presentation directly (`@State private var showSheet` + `.sheet(isPresented:)` right
/// here on the `Section`). That's a presentation anchored to a `List` ROW, not the List's own
/// root — and `AccountUITests.testDeleteAccountEndToEnd` reproduced 5/5 under the full suite (T5's
/// investigation, with `os.Logger` instrumentation): tapping "Delete account" DID flip `showSheet`
/// true and the sheet genuinely started presenting, but ~1.10-1.104s later (millisecond-consistent
/// across every run — not a fuzzy race) it silently flipped back to `false` with no user
/// interaction, and the unified log showed UIKit's
/// "Attempt to present ... while a presentation is in progress" right at that instant. Root cause:
/// a **second** List-hosted presentation attempt colliding with this row's own — `AccountSection`
/// above it in the same `List` loads the profile over the network on first appearance (plan 15:
/// `SessionStore.loadProfileIfNeeded()`, once per session) and, on a brand-new account (this
/// test's own shape: sign up → straight to Settings → straight to Delete, so the fetch is still in
/// flight), flips a loading spinner into 2-3 real rows moments later, reflowing the whole `List`
/// (UICollectionView-backed under SwiftUI) at just the wrong instant.
///
/// The fix: this row no longer owns any presentation state at all — `showSheet` is a `@Binding`
/// the PARENT (`SettingsView`) owns and presents from at its own List root, alongside the
/// pre-existing sign-out `.confirmationDialog` and How-to-Stash `.fullScreenCover`, neither of
/// which ever exhibited this bug precisely because they're root-anchored, not row-anchored. This
/// row's only job now is flipping that binding true.
struct DeleteAccountSection: View {
    @Binding var showSheet: Bool

    var body: some View {
        Section {
            Button(role: .destructive) {
                showSheet = true
            } label: {
                // Plan 16: DESIGN.md's `destructive` (5.06:1 on white); the system red a
                // destructive List button draws is 3.55:1.
                Text("Delete account")
                    .foregroundStyle(StashColor.destructive)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .accessibilityIdentifier("settings.deleteAccount")
        } footer: {
            // Plan 16: `muted` — the consequences have to be readable (the system footer grey
            // is ~3.3:1 on the grouped background).
            settingsCaption("Permanently deletes your account and everything in it: every item, file, "
                            + "transcript, note, and conversation. Your phone number is unlinked and any "
                            + "subscription is canceled. This cannot be undone.")
        }
    }
}

/// The delete-account confirm sheet's actual content (Plan 14 fix wave B extraction) — presented
/// from `SettingsView`'s own root `.sheet(isPresented:)`, never from `DeleteAccountSection`'s row
/// (see that type's doc comment for the presentation-race bug this fixes). Owns its own
/// `confirmation`/`isDeleting`/`errorMessage`: a `.sheet` content view is freshly instantiated on
/// every presentation, so there's no need to lift this state up to the root just because the
/// presentation TRIGGER lives there — only the boolean that opens/closes the sheet does.
///
/// Unlike web (an `AlertDialog` that keeps the whole page underneath), this uses a `.medium`
/// sheet — roomy enough for the longer consequence copy on a phone-width screen.
///
/// The deletion itself runs in `SessionStore.deleteAccount(userId:)` (plan 15, L7), which outlives
/// this sheet: on a confirmed deletion it purges this device's state (session, Outbox, recordings,
/// staged files, pending edits, the App Group subscription-gate cache, the library caches) and
/// lands on the sign-in screen with the "Your account was deleted." banner — which also takes this
/// sheet away. A request that times out (up to 120 s) or otherwise ends without a clear answer is
/// followed by asking the server whether the account still exists, so a deletion that finished
/// after the app stopped waiting is still recognized. Otherwise the sheet stays open with an inline
/// message saying what's known, and the user can try again (the edge function's own contract:
/// every step before the final `auth.admin.deleteUser` is safe to retry).
struct DeleteAccountConfirmSheet: View {
    let userId: UUID

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    /// Bold Text, for the one run of the confirmation copy set in its own face (`confirmWord`).
    @Environment(\.legibilityWeight) private var legibilityWeight
    @State private var confirmation = ""
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @FocusState private var fieldFocused: Bool

    private static let confirmWord = "DELETE"

    /// The field's and the buttons' minimum target, in this sheet's own points (plan 16): 46, not
    /// HIG's 44, because iOS 26 draws a sheet that isn't at its largest detent — this one's
    /// `.medium`, at the default text sizes — as a floating card scaled to about 0.96 (measured on
    /// iOS 26.5: a 44 pt control in it is 42.2 pt on screen). 46 × 0.96 is 44.2. Only the field
    /// grows (2 pt); the buttons' targets overhang their words, so nothing else moves.
    private static let minimumTarget: CGFloat = 46

    private var canDelete: Bool { confirmation == Self.confirmWord && !isDeleting }

    var body: some View {
        // Plan 16: centred in the sheet while it fits, scrolling at the larger text sizes (the
        // sheet also opens full height at the accessibility sizes — `SettingsView`).
        GeometryReader { geo in
            ScrollView {
                content
                    .padding(24)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
        }
        // Guards against a swipe-to-dismiss mid-delete (web parity: the AlertDialog's own
        // `handleOpenChange` refuses to close while `deleting` is true) — `interactiveDismissDisabled`
        // replaces the old custom `Binding` setter now that presentation lives at the root and this
        // view no longer has direct write access to the `showSheet` boolean.
        .interactiveDismissDisabled(isDeleting)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Delete your account?")
                .stashFont(.readingMedium)
                .foregroundStyle(StashColor.ink)
                .accessibilityAddTraits(.isHeader)

            // Supporting text (15 pt), with the word to type in Semibold at the same size and
            // curve — a run inside the concatenation takes its face from `legibilityWeight`.
            (Text("This removes your whole stash and signs you out everywhere. Type ")
                + Text(Self.confirmWord).font(StashType.Role.custom(.semibold, size: 15).font(legibilityWeight))
                + Text(" to confirm."))
                .stashFont(.secondary)
                .foregroundStyle(StashColor.muted)
                .fixedSize(horizontal: false, vertical: true)

            // Plan 16: the placeholder in `muted` (the system's is 1.7:1), a field that grows with
            // its text (`minHeight`), and a tap anywhere in it focuses it — not only on its text
            // line (simultaneous, so the field's own caret and selection taps are untouched).
            TextField(Self.confirmWord, text: $confirmation,
                      prompt: Text(Self.confirmWord).foregroundStyle(StashColor.muted))
                .focused($fieldFocused)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .disabled(isDeleting)
                .stashFont(.mono(.subheadline))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(minHeight: Self.minimumTarget)
                .background(StashColor.violet300.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous)
                        .strokeBorder(StashColor.hairline, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous))
                .simultaneousGesture(TapGesture().onEnded { fieldFocused = true })
                .accessibilityIdentifier("settings.deleteAccount.field")
                .accessibilityLabel("Type \(Self.confirmWord) to confirm")

            if let errorMessage {
                Text(errorMessage)
                    .stashFont(.meta)
                    .foregroundStyle(StashColor.destructive)
                    .accessibilityIdentifier("settings.deleteAccount.error")
            }

            // Side by side while they fit; stacked once the text is too big for one line (the
            // destructive action first, each on its own `minimumTarget` line, 50 pt apart centre
            // to centre).
            ViewThatFits(in: .horizontal) {
                HStack {
                    cancelButton
                    Spacer()
                    deleteButton
                }
                VStack(spacing: 4) {
                    deleteButton.frame(maxWidth: .infinity, minHeight: Self.minimumTarget)
                    cancelButton.frame(maxWidth: .infinity, minHeight: Self.minimumTarget)
                }
            }
            // Plain text buttons whose labels carry the target (`stashMinimumHitTarget`, as
            // `.stashPlain` does at 44); their colours are set here, since a plain button doesn't
            // tint itself.
            .buttonStyle(.plain)
        }
    }

    private var cancelButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Cancel").stashMinimumHitTarget(Self.minimumTarget)
        }
        .foregroundStyle(isDeleting ? StashColor.faint : StashColor.violet600)
        .disabled(isDeleting)
        .accessibilityIdentifier("settings.deleteAccount.cancel")
    }

    /// DESIGN.md's `destructive` (5.06:1 on the white sheet) while it can act — the system red a
    /// destructive button draws is 3.55:1 — and `faint` while it's disabled (the only use `faint`
    /// has for text).
    private var deleteButton: some View {
        Button(role: .destructive) {
            Task { await performDelete() }
        } label: {
            Group {
                if isDeleting {
                    ProgressView().tint(StashColor.destructive)
                } else {
                    Text("Delete everything")
                        .foregroundStyle(canDelete ? StashColor.destructive : StashColor.faint)
                }
            }
            .stashMinimumHitTarget(Self.minimumTarget)
        }
        .disabled(!canDelete)
        .accessibilityIdentifier("settings.deleteAccount.confirm")
    }

    private func performDelete() async {
        // Read while this sheet is still installed: a confirmed deletion signs the app out, and
        // the root swaps this sheet's whole hierarchy for the sign-in screen before this returns.
        let session = self.session
        let dismiss = self.dismiss
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }
        switch await session.deleteAccount(userId: userId) {
        case .deleted:
            dismiss()
        case .failed(let message):
            errorMessage = message
        }
    }
}
