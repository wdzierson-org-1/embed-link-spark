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

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: typeIcon)
                Text(item.type.rawValue.uppercased())
            }
            .font(StashType.kicker())
            .stashTracking(0.10, size: 11)
            .foregroundStyle(StashColor.ink)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(StashColor.wash, in: Capsule())

            if item.type == .link, !domain.isEmpty {
                Text(domain)
                    .font(StashType.meta())
                    .foregroundStyle(StashColor.faint)
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
