import SwiftUI
import StashKit

/// Detail-sheet eyebrow: a `wash`-filled type pill (icon + uppercase type name, `kicker` face) +
/// the source hint alongside it — the domain for link items, else nothing (dates move to Task 7's
/// Details drawer, per the brief). Port of `EditItemDetailsTab.tsx`'s eyebrow row, simplified per
/// this task's brief to a single neutral `wash` tint rather than the web's full per-type tinted
/// spectrum (`getTypeChip`) — that spectrum stays a follow-up, not part of this task's scope.
struct DetailEyebrow: View {
    let item: Item

    private var domain: String { domainOf(item.url) }

    /// Plan 16: the pill is the `kicker` role in `ink` (its glyph takes the same size), the domain
    /// `meta` in `muted` (`faint` was 2.61:1 here). Both scale. The pill's one word keeps its line
    /// and its width (SwiftUI breaks a squeezed word mid-word at the accessibility sizes); a long
    /// domain beside it wraps instead.
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: typeIcon)
                Text(item.type.rawValue)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .stashKicker(StashColor.ink)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(StashColor.wash, in: Capsule())
            .layoutPriority(1)

            if item.type == .link, !domain.isEmpty {
                Text(domain)
                    .stashFont(.meta)
                    .foregroundStyle(StashColor.muted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("detail.eyebrow")
    }

    private var accessibilityText: String {
        let type = item.type.rawValue.uppercased()
        return (item.type == .link && !domain.isEmpty) ? "\(type) \(domain)" : type
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
