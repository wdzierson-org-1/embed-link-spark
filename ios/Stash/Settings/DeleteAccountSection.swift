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
/// Unlike web (an `AlertDialog` that keeps the whole page underneath), this uses a `.medium`
/// sheet — consistent with this app's other confirm-with-typed-text flow
/// (`CardNoteEditorSheet`'s own detent) and roomy enough for the longer consequence copy on a
/// phone-width screen.
///
/// Success routes through `SessionStore.completeAccountDeletion(userId:)` — which purges this
/// device's local state (Outbox, staged files, the App Group subscription-gate cache, and the
/// Keychain session) and lands on the sign-in screen with the "Your account was deleted." banner
/// — never this view's own job to know about any of that. Failure keeps the sheet open with an
/// inline error and the account fully intact (the edge function's own contract: every step before
/// the final `auth.admin.deleteUser` is safe to retry).
struct DeleteAccountSection: View {
    let userId: UUID

    @Environment(SessionStore.self) private var session
    @State private var showSheet = false
    @State private var confirmation = ""
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private static let confirmWord = "DELETE"

    var body: some View {
        Section {
            Button(role: .destructive) {
                confirmation = ""
                errorMessage = nil
                showSheet = true
            } label: {
                Text("Delete account").frame(maxWidth: .infinity, alignment: .center)
            }
            .accessibilityIdentifier("settings.deleteAccount")
        } footer: {
            Text("Permanently deletes your account and everything in it: every item, file, "
                 + "transcript, note, and conversation. Your phone number is unlinked and any "
                 + "subscription is canceled. This cannot be undone.")
        }
        .sheet(isPresented: Binding(
            get: { showSheet },
            // Guards against a swipe-to-dismiss mid-delete (web parity: the AlertDialog's own
            // `handleOpenChange` refuses to close while `deleting` is true).
            set: { next in if !isDeleting { showSheet = next } }
        )) {
            deleteSheet
                .presentationDetents([.medium])
        }
    }

    private var deleteSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Delete your account?")
                .font(StashType.bodyMedium(17))
                .foregroundStyle(StashColor.ink)

            (Text("This removes your whole stash and signs you out everywhere. Type ")
                + Text(Self.confirmWord).font(StashType.bodySemibold(14))
                + Text(" to confirm."))
                .font(StashType.body())
                .foregroundStyle(StashColor.muted)

            TextField(Self.confirmWord, text: $confirmation)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .disabled(isDeleting)
                .font(StashType.mono(15))
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(StashColor.violet300.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous)
                        .strokeBorder(StashColor.hairline, lineWidth: 1)
                )
                .accessibilityIdentifier("settings.deleteAccount.field")
                .accessibilityLabel("Type \(Self.confirmWord) to confirm")

            if let errorMessage {
                Text(errorMessage)
                    .font(StashType.meta())
                    .foregroundStyle(StashColor.destructive)
                    .accessibilityIdentifier("settings.deleteAccount.error")
            }

            HStack {
                Button("Cancel") { showSheet = false }
                    .disabled(isDeleting)
                    .accessibilityIdentifier("settings.deleteAccount.cancel")
                Spacer()
                Button(role: .destructive) {
                    Task { await performDelete() }
                } label: {
                    if isDeleting {
                        ProgressView().tint(StashColor.destructive)
                    } else {
                        Text("Delete everything")
                    }
                }
                .disabled(confirmation != Self.confirmWord || isDeleting)
                .accessibilityIdentifier("settings.deleteAccount.confirm")
            }
        }
        .padding(24)
    }

    private func performDelete() async {
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }
        guard let accessToken = try? await StashClient.shared.auth.session.accessToken else {
            errorMessage = "Your session expired. Sign out and back in, then try again."
            return
        }
        do {
            _ = try await AccountDeleter().delete(using: FunctionsAccountDeletionTransport(), accessToken: accessToken)
            showSheet = false
            await session.completeAccountDeletion(userId: userId)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private static func message(for error: Error) -> String {
        switch error {
        case AccountDeletionError.unauthorized:
            return "Your session expired. Sign out and back in, then try again."
        case AccountDeletionError.forbidden(let message):
            return message
        case AccountDeletionError.serverError(let message):
            return message
        case AccountDeletionError.transport:
            return "Couldn't reach Stash. Check your connection and try again."
        default:
            return "Nothing was removed. Please try again."
        }
    }
}
