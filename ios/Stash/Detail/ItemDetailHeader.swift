import SwiftUI
import StashKit

/// Detail-sheet header: type icon + read-only title, description, relative date, and (when
/// public) a small "Public" badge. When the item is public *and* carries a supplemental note,
/// also renders the note as a yellow sticky-note card — the same public-feed feature
/// `ItemCardView`'s corner badge hints at, shown here in full rather than as an icon.
struct ItemDetailHeader: View {
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: typeIcon)
                    .foregroundStyle(.secondary)
                    .imageScale(.large)
                titleText
                Spacer(minLength: 8)
                if item.isPublic { publicBadge }
            }
            if let description = item.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("detail.description")
            }
            Text(item.createdAt, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityIdentifier("detail.date")
            stickyNote
        }
    }

    private var title: String {
        let trimmed = item.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    /// Styled to look like the editable title field Plan 2's editor will make real —
    /// this build is read-only, so it's plain Text, not a TextField.
    private var titleText: some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("detail.title")
    }

    private var publicBadge: some View {
        Label("Public", systemImage: "globe")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.15), in: Capsule())
            .foregroundStyle(.green)
            .accessibilityIdentifier("detail.publicBadge")
    }

    @ViewBuilder private var stickyNote: some View {
        if item.isPublic, let note = item.supplementalNote, !note.isEmpty {
            Text(renderTipTap(note))
                .font(.subheadline)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.yellow.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
                .rotationEffect(.degrees(-1.5))
                .accessibilityIdentifier("detail.stickyNote")
        }
    }

    private var typeIcon: String {
        switch item.type {
        case .text: "note.text"
        case .link: "link"
        case .image: "photo"
        case .audio: "waveform"
        case .video: "video"
        case .document: "doc.richtext"
        case .collection: "folder"
        case .unknown: "questionmark.square"
        }
    }
}
