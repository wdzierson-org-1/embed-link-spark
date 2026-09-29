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
/// safe here.
///
/// Plan 15: the username comes from `SessionStore`'s per-session profile (`user_profiles` by id,
/// web `useProfile.ts`'s query) — fetched once per signed-in session, not on every visit, so the
/// row is instant after the first. The store owns that request, so leaving Settings mid-load can't
/// cancel it into a sticky "Couldn't load your profile." (M6); the message shows only for a real
/// failure and goes away as soon as a later visit's retry succeeds.
struct AccountSection: View {
    let userId: UUID

    @Environment(SessionStore.self) private var session
    @State private var didCopy = false

    private var email: String { StashClient.shared.auth.currentUser?.email ?? "" }
    private var load: ProfileLoad { session.profileLoad(for: userId) }
    private var username: String? {
        if case .loaded(let profile) = load { return profile.username }
        return nil
    }
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
            switch load {
            case .idle, .loading:
                ProgressView()
            case .loaded, .failed:
                HStack {
                    Text("Username").foregroundStyle(StashColor.muted)
                    Spacer()
                    Text(username ?? "—")
                        .accessibilityIdentifier("settings.account.username")
                }
                feedURLRow
                if load == .failed {
                    Text("Couldn't load your profile.")
                        .font(StashType.meta())
                        .foregroundStyle(StashColor.destructive)
                        .accessibilityIdentifier("settings.account.error")
                }
            }
        }
        .onAppear { session.loadProfileIfNeeded() }
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
}
