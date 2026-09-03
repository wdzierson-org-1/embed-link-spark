import SwiftUI
import StashKit
import UIKit

/// Sharing (DESIGN.md "Sharing row states"): a restyle, in place, of `PublicToggleSection` — same
/// data and actions (public/private toggle, un-share confirmation, sticky-note lifecycle), now
/// drawn per spec as an icon tile + two-line copy + violet switch, with a feed-link copy chip when
/// public. Every identifier `testTagsAndPublicSmoke` depends on (`detail.public.toggle`,
/// `detail.public.sticky`, `detail.public.error`) is unchanged from `PublicToggleSection` — only
/// the visual treatment moved; see that type's now-superseded doc comment for the full behavioral
/// rationale (immediate save on share, confirm-first on un-share when a note is present).
///
/// Fix round 1 (review): the feed-link chip is now gated on a fully-loaded, non-empty `username`
/// (see `feedURL`/`feedLinkSection`) instead of rendering — and being copyable — the instant
/// `isPublic` flips true, which previously raced `username`'s async load and could copy a bare
/// `gostash.it/feed/`. The URL formula itself moved to `PublicFeedURL.make(username:)`, shared
/// with `AccountSection`'s identical Settings-tab row rather than kept as two copies.
struct SharingSection: View {
    let item: Item
    let editor: ItemEditor
    @Binding var supplementalNote: String
    var onSaved: (Item) -> Void

    @State private var isToggling = false
    @State private var showUnshareConfirm = false
    @State private var errorMessage: String?
    @State private var username: String?
    @State private var isLoadingUsername = false
    @State private var didCopyFeedLink = false

    /// `nil` until `username` has actually loaded (Fix round 1, review finding #2: the chip used
    /// to render — and be copyable — the instant `isPublic` flipped true, while `username` was
    /// still its initial `nil`, producing a bare `gostash.it/feed/` with nothing after the
    /// trailing slash). `PublicFeedURL.make` is only ever called once `username` is confirmed
    /// non-empty, so every value this property can produce is already a complete, correct URL.
    private var feedURL: String? {
        guard let username, !username.isEmpty else { return nil }
        return PublicFeedURL.make(username: username)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            microLabel
            statusRow
            if item.isPublic {
                feedLinkSection
                stickyNoteField
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(StashType.meta())
                    .foregroundStyle(StashColor.destructive)
                    .accessibilityIdentifier("detail.public.error")
            }
        }
        .task(id: item.isPublic) {
            guard item.isPublic, username == nil else { return }
            isLoadingUsername = true
            await loadUsername()
            isLoadingUsername = false
        }
        .confirmationDialog("Make private? The sticky note will be removed.",
                             isPresented: $showUnshareConfirm, titleVisibility: .visible) {
            Button("Make Private", role: .destructive) { Task { await apply(isPublic: false) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Rows

    private var microLabel: some View {
        Text("SHARING")
            .font(StashType.microLabel())
            .stashTracking(0.11, size: 11)
            .foregroundStyle(StashColor.faint)
            .padding(.bottom, 7)
            .overlay(alignment: .bottom) {
                Rectangle().fill(StashColor.hairline).frame(height: 1)
            }
    }

    private var statusRow: some View {
        HStack(spacing: 12) {
            statusGroup
            Spacer(minLength: 8)
            Toggle(isOn: Binding(get: { item.isPublic }, set: { handleToggle($0) })) { EmptyView() }
                .labelsHidden()
                .tint(StashColor.violet600)
                .disabled(isToggling)
                .accessibilityIdentifier("detail.public.toggle")
                .accessibilityLabel(item.isPublic ? "On your public feed" : "Private")
        }
    }

    /// Tile + two-line copy, isolated as its own leaf accessibility element (mirrors
    /// `DetailEyebrow`'s pattern) so `detail.sharing` reports "Private"/"On your public feed"
    /// without swallowing the sibling `Toggle`'s own identifier into a combined label.
    private var statusGroup: some View {
        HStack(spacing: 12) {
            tile
            VStack(alignment: .leading, spacing: 2) {
                Text(item.isPublic ? "On your public feed" : "Private")
                    .font(StashType.bodyMedium(13.5))
                    .foregroundStyle(StashColor.ink)
                Text(item.isPublic ? "Anyone with your feed link can see this item" : "Only you can see this item")
                    .font(StashType.meta())
                    .foregroundStyle(StashColor.faint)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.isPublic
            ? "On your public feed, Anyone with your feed link can see this item"
            : "Private, Only you can see this item")
        .accessibilityIdentifier("detail.sharing")
    }

    /// 40pt circle — `wash` + `lock` at rest, violet-tinted + `globe` once shared (DESIGN.md
    /// "Sharing row states": "private = grey lock tile ... Public = violet globe tile").
    private var tile: some View {
        Image(systemName: item.isPublic ? "globe" : "lock")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(item.isPublic ? StashColor.violet600 : StashColor.muted)
            .frame(width: 40, height: 40)
            .background(item.isPublic ? StashColor.violet600.opacity(0.12) : StashColor.wash, in: Circle())
    }

    /// Gates the feed-link chip on a loaded, non-empty `username` (Fix round 1, review finding
    /// #2): a muted "Loading feed link…" placeholder while the fetch is in flight, the real chip
    /// once `feedURL` resolves, and — on failure or an empty username — nothing at all, rather
    /// than ever showing (or letting the user copy) an incomplete `gostash.it/feed/` URL.
    @ViewBuilder
    private var feedLinkSection: some View {
        if let feedURL {
            feedLinkChip(feedURL)
        } else if isLoadingUsername {
            Text("Loading feed link…")
                .font(StashType.meta())
                .foregroundStyle(StashColor.faint)
                .padding(.leading, 52)
        }
    }

    /// Feed-link chip: mono URL (truncated) + copy button — DESIGN.md "feed-link chip
    /// (`gostash.it/feed/{username}`) with copy-confirm". 180ms fade/slide-in per DESIGN.md
    /// Motion. Only ever called with a complete, non-empty `feedURL` (see `feedLinkSection`), so
    /// the copy button needs no separate "is the URL complete yet" disabled state — by the time
    /// this view exists at all, it always is.
    private func feedLinkChip(_ feedURL: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(feedURL.replacingOccurrences(of: "https://", with: ""))
                    .font(StashType.mono(11))
                    .foregroundStyle(StashColor.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button {
                    copyFeedLink(feedURL)
                } label: {
                    Image(systemName: didCopyFeedLink ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(StashColor.violet600)
                }
                .accessibilityLabel(didCopyFeedLink ? "Copied" : "Copy public feed link")
                .accessibilityIdentifier("detail.sharing.feedLink.copy")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(StashColor.paper.opacity(0.85), in: Capsule())
            .overlay(Capsule().strokeBorder(StashColor.hairline, lineWidth: 1))

            Text("Turning this off removes it from your feed.")
                .font(StashType.meta())
                .foregroundStyle(StashColor.faint)
        }
        .padding(.leading, 52)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(.easeInOut(duration: 0.18), value: item.isPublic)
        .accessibilityIdentifier("detail.sharing.feedLink")
    }

    private var stickyNoteField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sticky note")
                .font(StashType.meta())
                .foregroundStyle(StashColor.muted)
            TextField("Add a quick note…", text: $supplementalNote, axis: .vertical)
                .font(StashType.body())
                .textFieldStyle(.plain)
                .padding(10)
                .background(Color.yellow.opacity(0.16), in: RoundedRectangle(cornerRadius: StashRadius.input))
                .accessibilityIdentifier("detail.public.sticky")
            Text("This note appears as a yellow sticky note on the public feed card.")
                .font(StashType.meta())
                .foregroundStyle(StashColor.faint)
        }
        .padding(.leading, 52)
    }

    // MARK: - Actions

    /// Turning ON is always a direct save; turning OFF only interrupts for confirmation when
    /// there's an actual sticky note to lose (empty/nil note → straight through, no dialog).
    private func handleToggle(_ newValue: Bool) {
        if !newValue, let note = item.supplementalNote, !note.isEmpty {
            showUnshareConfirm = true
            return
        }
        Task { await apply(isPublic: newValue) }
    }

    private func apply(isPublic: Bool) async {
        isToggling = true
        errorMessage = nil
        defer { isToggling = false }
        let patch = editor.togglePublic(item: item, to: isPublic)
        do {
            let merged = try await editor.save(itemId: item.id, patch: patch)
            onSaved(merged)
        } catch {
            errorMessage = "Couldn't update — try again."
        }
    }

    private func copyFeedLink(_ feedURL: String) {
        UIPasteboard.general.string = feedURL
        didCopyFeedLink = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopyFeedLink = false
        }
    }

    private func loadUsername() async {
        guard let userId = StashClient.shared.auth.currentUser?.id else { return }
        struct ProfileRow: Decodable { let username: String }
        do {
            let data = try await StashClient.shared.from("user_profiles")
                .select("username")
                .eq("id", value: userId.uuidString)
                .single()
                .execute().data
            username = try JSONDecoder().decode(ProfileRow.self, from: data).username
        } catch {
            // Non-fatal, same fire-and-forget precedent as `saveAttributes` in ItemDetailView:
            // `username` just stays `nil`, so `feedURL` stays `nil` and `feedLinkSection` simply
            // renders nothing (see its own doc comment) rather than a broken partial URL.
        }
    }
}
