import SwiftUI
import StashKit
import UIKit

/// Sharing (DESIGN.md "Sharing row states"): a restyle, in place, of `PublicToggleSection` — same
/// data and actions (public/private toggle, un-share confirmation, sticky-note lifecycle), now
/// drawn per spec as an icon tile + two-line copy + violet switch, with a feed-link copy chip when
/// public. Every identifier `testPublicSmoke` depends on (`detail.public.toggle`,
/// `detail.public.sticky`, `detail.public.error`) is unchanged from `PublicToggleSection` — only
/// the visual treatment moved; see that type's now-superseded doc comment for the full behavioral
/// rationale (immediate save on share, confirm-first on un-share when a note is present).
///
/// Fix round 1 (review): the feed-link chip is now gated on a fully-loaded, non-empty `username`
/// (see `feedURL`/`feedLinkSection`) instead of rendering — and being copyable — the instant
/// `isPublic` flips true, which previously raced `username`'s async load and could copy a bare
/// `gostash.it/feed/`. The URL formula itself moved to `PublicFeedURL.make(username:)`, shared
/// with `AccountSection`'s identical Settings-tab row rather than kept as two copies.
///
/// Plan 15 (L5): the switch is optimistic — `setPublic` (owned by `ItemDetailView`, which flips
/// `item.isPublic` at once, saves through the sheet's save generation, and flips back on failure)
/// returns whether the save landed; this section only shows the inline error when it didn't.
///
/// Plan 15 (snappiness): the feed link's username is `SessionStore`'s per-session profile, loaded
/// once per signed-in session — not refetched every time a public item's sheet opens.
struct SharingSection: View {
    let item: Item
    @Binding var supplementalNote: String
    var setPublic: (Bool) async -> Bool

    @Environment(SessionStore.self) private var session
    @State private var isToggling = false
    @State private var showUnshareConfirm = false
    @State private var errorMessage: String?
    @State private var didCopyFeedLink = false
    /// The feed link's copy glyph grows with the URL beside it (11 pt beside its 11, like a text
    /// field's clear button). A scaled metric on a system symbol font: the same glyph set in a
    /// custom face relative to `.caption2` stayed ~11 pt at every size (measured at xxxL and AX3).
    @ScaledMetric(relativeTo: .caption2) private var copyGlyphSize: CGFloat = 11
    /// The sticky note field's keyboard focus — so a tap anywhere on its note box focuses it.
    @FocusState private var stickyFocused: Bool

    private var username: String? { session.profile?.username }
    private var isLoadingUsername: Bool { session.profileLoad == .loading }

    /// `nil` until `username` has actually loaded (Fix round 1, review finding #2: the chip used
    /// to render — and be copyable — the instant `isPublic` flipped true, while `username` was
    /// still its initial `nil`, producing a bare `gostash.it/feed/` with nothing after the
    /// trailing slash). `PublicFeedURL.make` itself now returns `nil` for a `nil`/empty username
    /// (final wave, item D2), so every value this property can produce is already a complete,
    /// correct URL.
    private var feedURL: String? { PublicFeedURL.make(username: username) }

    var body: some View {
        // Outer spacing 0 — `SectionHeader` already carries its own top/bottom rhythm
        // (`DetailLayout.section`/`.gap`); the original `spacing: 10` between the label and
        // `statusRow` moves onto the inner group below instead, so it isn't double-counted on
        // top of `SectionHeader`'s own bottom gap.
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "SHARING")

            VStack(alignment: .leading, spacing: 10) {
                statusRow
                if item.isPublic {
                    feedLinkSection
                    stickyNoteField
                }
                if let errorMessage {
                    Text(errorMessage)
                        .stashFont(.meta)
                        .foregroundStyle(StashColor.destructive)
                        .accessibilityIdentifier("detail.public.error")
                }
            }
        }
        .task(id: item.isPublic) {
            if item.isPublic { session.loadProfileIfNeeded() }
        }
        .confirmationDialog("Make private? The sticky note will be removed.",
                             isPresented: $showUnshareConfirm, titleVisibility: .visible) {
            Button("Make Private", role: .destructive) { Task { await apply(isPublic: false) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Rows

    /// Plan 16: the switch is the system one (VoiceOver already hears a switch that is on or off),
    /// so its name stays the same in both states — "Share on your public feed" — instead of
    /// switching between "Private" and "On your public feed". The tile and copy read the state;
    /// the switch sits in a row at least 44 pt tall, and the copy wraps at large text sizes.
    private var statusRow: some View {
        HStack(spacing: 12) {
            statusGroup
            Spacer(minLength: 8)
            Toggle(isOn: Binding(get: { item.isPublic }, set: { handleToggle($0) })) { EmptyView() }
                .labelsHidden()
                .tint(StashColor.violet600)
                .disabled(isToggling)
                .accessibilityIdentifier("detail.public.toggle")
                .accessibilityLabel("Share on your public feed")
        }
        .frame(minHeight: 44)
    }

    /// Tile + two-line copy, isolated as its own leaf accessibility element (mirrors
    /// `DetailEyebrow`'s pattern) so `detail.sharing` reports "Private"/"On your public feed"
    /// without swallowing the sibling `Toggle`'s own identifier into a combined label.
    ///
    /// Plan 16: the state line is `secondaryMedium` (was a 13.5 pt Medium), the explanation `meta`
    /// in `muted` (was `faint`).
    private var statusGroup: some View {
        HStack(spacing: 12) {
            tile
            VStack(alignment: .leading, spacing: 2) {
                Text(item.isPublic ? "On your public feed" : "Private")
                    .stashFont(.secondaryMedium)
                    .foregroundStyle(StashColor.ink)
                Text(item.isPublic ? "Anyone with your feed link can see this item" : "Only you can see this item")
                    .stashFont(.meta)
                    .foregroundStyle(StashColor.muted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.isPublic
            ? "On your public feed, Anyone with your feed link can see this item"
            : "Private, Only you can see this item")
        .accessibilityIdentifier("detail.sharing")
    }

    /// 40pt circle — `wash` + `lock` at rest, violet-tinted + `globe` once shared (DESIGN.md
    /// "Sharing row states": "private = grey lock tile ... Public = violet globe tile"). A picture
    /// of the state, not a control (the switch beside it is): its glyph stays a fixed size, like
    /// the tile (plan 16 — `StashType.decorative`; `statusGroup` reads the state to VoiceOver).
    private var tile: some View {
        Image(systemName: item.isPublic ? "globe" : "lock")
            .font(StashType.decorative(.medium, size: 15))
            .foregroundStyle(item.isPublic ? StashColor.violet600 : StashColor.muted)
            .frame(width: 40, height: 40)
            .background(item.isPublic ? StashColor.violet600.opacity(0.12) : StashColor.wash, in: Circle())
            .accessibilityHidden(true)
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
                .stashFont(.meta)
                .foregroundStyle(StashColor.muted)
                .padding(.leading, 52)
        }
    }

    /// Feed-link chip: mono URL (truncated) + copy button — DESIGN.md "feed-link chip
    /// (`gostash.it/feed/{username}`) with copy-confirm". 180ms fade/slide-in per DESIGN.md
    /// Motion. Only ever called with a complete, non-empty `feedURL` (see `feedLinkSection`), so
    /// the copy button needs no separate "is the URL complete yet" disabled state — by the time
    /// this view exists at all, it always is.
    /// Plan 16: the URL is `mono(.caption2)` and scales, wrapping onto up to three lines (the
    /// capsule becomes a rounded rectangle while it does) rather than losing its middle; the copy
    /// button's glyph grows with it (11 pt beside the URL's 11, like a text field's clear button)
    /// and takes taps across 44 pt (`.stashPlain`), named for VoiceOver and the Large Content
    /// Viewer.
    private func feedLinkChip(_ feedURL: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(feedURL.replacingOccurrences(of: "https://", with: ""))
                    .stashFont(.mono(.caption2))
                    .foregroundStyle(StashColor.muted)
                    .lineLimit(3)
                    .truncationMode(.middle)
                Button {
                    copyFeedLink(feedURL)
                } label: {
                    Image(systemName: didCopyFeedLink ? "checkmark" : "doc.on.doc")
                        .font(.system(size: copyGlyphSize, weight: .medium))
                        .foregroundStyle(StashColor.violet600)
                }
                .buttonStyle(.stashPlain)
                .stashIconControl(didCopyFeedLink ? "Copied" : "Copy public feed link",
                                  systemImage: didCopyFeedLink ? "checkmark" : "doc.on.doc")
                .accessibilityIdentifier("detail.sharing.feedLink.copy")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(StashColor.paper.opacity(0.85),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(StashColor.hairline, lineWidth: 1))

            Text("Turning this off removes it from your feed.")
                .stashFont(.meta)
                .foregroundStyle(StashColor.muted)
        }
        .padding(.leading, 52)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(.easeInOut(duration: 0.18), value: item.isPublic)
        .accessibilityIdentifier("detail.sharing.feedLink")
    }

    /// Plan 16: the note is reading text (17), its placeholder `muted` (`prompt:` — the system
    /// grey was 1.7:1), and the whole note box — at least 44 pt tall — takes the tap that focuses
    /// it: the text field itself is only its line of text (21 pt), and a tap on the box's padding
    /// used to do nothing. The box's fill takes those taps from behind the field, so a tap on the
    /// text still goes to the text (caret, selection).
    private var stickyNoteField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sticky note")
                .stashFont(.meta)
                .foregroundStyle(StashColor.muted)
            TextField("Sticky note", text: $supplementalNote,
                      prompt: Text("Add a quick note…").foregroundStyle(StashColor.muted), axis: .vertical)
                .stashFont(.reading)
                .textFieldStyle(.plain)
                .focused($stickyFocused)
                .padding(10)
                .frame(minHeight: 44)
                .background {
                    RoundedRectangle(cornerRadius: StashRadius.input)
                        .fill(Color.yellow.opacity(0.16))
                        .onTapGesture { stickyFocused = true }
                }
                .accessibilityIdentifier("detail.public.sticky")
            Text("This note appears as a yellow sticky note on the public feed card.")
                .stashFont(.meta)
                .foregroundStyle(StashColor.muted)
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
        if !(await setPublic(isPublic)) {
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
}
