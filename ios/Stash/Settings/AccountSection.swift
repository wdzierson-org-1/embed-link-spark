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
        Section {
            // Plan 16: label and value side by side while the value fits, stacked (and wrapping)
            // when it doesn't — an email is never cut to a fragment.
            SettingsValueRow(label: "Email") {
                // A line-break opportunity after the "@" (a zero-width space), so a wrapped email
                // breaks between name and domain instead of being hyphenated mid-word
                // ("dzier-son.com" at AX3). VoiceOver (and tests) read the plain address.
                Text(email.replacingOccurrences(of: "@", with: "@\u{200B}"))
                    .accessibilityLabel(email)
                    .accessibilityIdentifier("settings.account.email")
            }
            switch load {
            case .idle, .loading:
                ProgressView()
            case .loaded, .failed:
                SettingsValueRow(label: "Username") {
                    Text(username ?? "—")
                        .accessibilityIdentifier("settings.account.username")
                }
                feedURLRow
                if load == .failed {
                    Text("Couldn't load your profile.")
                        .stashFont(.meta)
                        .foregroundStyle(StashColor.destructive)
                        .accessibilityIdentifier("settings.account.error")
                }
            }
        } header: {
            settingsCaption("Account")
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
                    // Plan 16: wraps (up to three lines) rather than losing its middle at the
                    // larger text sizes.
                    Text(feedURL)
                        .stashFont(.meta)
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .accessibilityIdentifier("settings.feedurl")
                    Spacer(minLength: 8)
                    // A 44 pt target (`.stashPlain`, which also keeps the tap on this button, not
                    // the row); named for VoiceOver and the Large Content Viewer, and says when
                    // it has copied.
                    Button {
                        copyFeedURL(feedURL)
                    } label: {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                            .foregroundStyle(StashColor.violet600)
                    }
                    .buttonStyle(.stashPlain)
                    .stashIconControl("Copy feed URL", systemImage: "doc.on.doc")
                    .accessibilityValue(didCopy ? "Copied" : "")
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
