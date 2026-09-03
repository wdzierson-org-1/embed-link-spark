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
struct SharingSection: View {
    let item: Item
    let editor: ItemEditor
    @Binding var supplementalNote: String
    var onSaved: (Item) -> Void

    @State private var isToggling = false
    @State private var showUnshareConfirm = false
    @State private var errorMessage: String?
    @State private var username: String?
    @State private var didCopyFeedLink = false

    /// Same `gostash.it/feed/{username}` shape `AccountSection`'s Settings-tab feed-URL row
    /// already builds — the app's one existing public-URL formula, not a new one invented here.
    private var feedURL: String { "https://gostash.it/feed/\(username ?? "")" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            microLabel
            statusRow
            if item.isPublic {
                feedLinkChip
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
            await loadUsername()
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
                .accessibilityLabel(item.isPublic ? "Public Feed" : "Private")
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

    /// Feed-link chip: mono URL (truncated) + copy button — DESIGN.md "feed-link chip
    /// (`gostash.it/feed/{username}`) with copy-confirm". 180ms fade/slide-in per DESIGN.md
    /// Motion.
    private var feedLinkChip: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(feedURL.replacingOccurrences(of: "https://", with: ""))
                    .font(StashType.mono(11))
                    .foregroundStyle(StashColor.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button {
                    copyFeedLink()
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

    private func copyFeedLink() {
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
            // the feed-link chip just shows an empty username segment until the next attempt.
        }
    }
}
