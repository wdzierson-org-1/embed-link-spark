import SwiftUI
import StashKit
import UIKit

/// Read-only account info (Task 7), scoped to exactly what the brief's prose asks for: email +
/// username + public feed URL with a copy button. Deliberately does NOT port
/// `AccountSettings.tsx`'s editable first/last/display-name fields or its "Save Changes" flow —
/// the brief's Produces section never mentions them, so this is a scope cut, not an oversight.
///
/// `email` reads `StashClient.shared.auth.currentUser` synchronously rather than threading it in
/// — same precedent `ItemTagsSection` already established: this view is only ever reachable once
/// `SessionStore` has resolved a signed-in session, so the non-throwing `currentUser` accessor is
/// safe here. `username` mirrors `useProfile.ts`'s query (`user_profiles`, not a `profiles`
/// table — the brief's own prose said "profiles table" loosely; the web's actual query is the
/// source of truth) — `.eq("id", value: userId)`, single row.
struct AccountSection: View {
    let userId: UUID

    @State private var username: String?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var didCopy = false

    private var email: String { StashClient.shared.auth.currentUser?.email ?? "" }
    /// `nil` while `username` hasn't loaded (or loaded empty) — `feedURLRow` gates on this so the
    /// row/copy button never renders a bare `gostash.it/feed/` (final wave, item D2).
    private var feedURL: String? { PublicFeedURL.make(username: username) }

    var body: some View {
        Section("Account") {
            HStack {
                Text("Email").foregroundStyle(StashColor.muted)
                Spacer()
                Text(email)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityIdentifier("settings.account.email")
            }
            if isLoading {
                ProgressView()
            } else {
                HStack {
                    Text("Username").foregroundStyle(StashColor.muted)
                    Spacer()
                    Text(username ?? "—")
                        .accessibilityIdentifier("settings.account.username")
                }
                feedURLRow
                if let errorMessage {
                    Text(errorMessage)
                        .font(StashType.meta())
                        .foregroundStyle(StashColor.destructive)
                        .accessibilityIdentifier("settings.account.error")
                }
            }
        }
        .task { await loadUsername() }
    }

    /// Gated on `feedURL` (item D2) — `PublicFeedURL.make` returns `nil` for a `nil`/empty
    /// username, so this row (and its copy button) never renders a bare `gostash.it/feed/`.
    @ViewBuilder
    private var feedURLRow: some View {
        if let feedURL {
            VStack(alignment: .leading, spacing: 6) {
                Text("Public Feed URL").foregroundStyle(StashColor.muted)
                HStack(spacing: 10) {
                    Text(feedURL)
                        .font(StashType.meta())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .accessibilityIdentifier("settings.feedurl")
                    Spacer(minLength: 8)
                    Button {
                        copyFeedURL(feedURL)
                    } label: {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("settings.feedurl.copy")
                }
            }
        }
    }

    private func copyFeedURL(_ feedURL: String) {
        UIPasteboard.general.string = feedURL
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopy = false
        }
    }

    private func loadUsername() async {
        defer { isLoading = false }
        struct ProfileRow: Decodable { let username: String }
        do {
            let data = try await StashClient.shared.from("user_profiles")
                .select("username")
                .eq("id", value: userId.uuidString)
                .single()
                .execute().data
            username = try JSONDecoder().decode(ProfileRow.self, from: data).username
        } catch {
            errorMessage = "Couldn't load your profile."
        }
    }
}
