import SwiftUI
import StashKit

/// V2 object card: real media, Montreal title, machine status, human words, ruled metadata.
/// The parent library owns its single tap target. Everything here, including the audio drawing
/// and note preview, opens that same detail sheet; no nested controls claim the card's taps.
struct ItemCardView: View {
    let item: Item
    @State private var collectionCount: Int?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var titleLineLimit: Int? { dynamicTypeSize.isAccessibilitySize ? nil : 2 }
    private func previewLineLimit(_ standard: Int) -> Int {
        dynamicTypeSize.isAccessibilitySize ? standard * 2 : standard
    }

    var body: some View {
        let status = item.attributes.enrichmentStatus(at: .now)
        // Only a pipeline-owned pending status starts a cursor. The shared helper validates its
        // timestamp and settles it to partial after ten minutes; an absent summary is not proof
        // that work is running (older or failed documents may never have one).
        if status == "pending" {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                cardBody(status: item.attributes.enrichmentStatus(at: context.date))
            }
        } else {
            cardBody(status: status)
        }
    }

    private func cardBody(status: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasHero {
                heroZone
                    .overlay(alignment: .topLeading) { kindTag.padding(10) }
                    .overlay(alignment: .topTrailing) {
                        if item.isPublic { CardKindTag(text: "public", inverted: true).padding(10) }
                    }
            }
            VStack(alignment: .leading, spacing: 10) {
                if !hasHero {
                    HStack(alignment: .top) {
                        kindTag
                        Spacer(minLength: 4)
                        if item.isPublic { CardKindTag(text: "public", inverted: true) }
                    }
                }
                Text(ItemDisplay.displayTitle(for: item))
                    .stashFont(.cardTitle)
                    .stashTracking(-0.018, role: .cardTitle)
                    .foregroundStyle(StashColor.ink)
                    .lineLimit(titleLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
                enrichmentLine(status: status)
                contentSection
                footer
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StashColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: StashRadius.object))
        .overlay(RoundedRectangle(cornerRadius: StashRadius.object).strokeBorder(StashColor.line, lineWidth: 1))
        .stashCardShadow()
    }

    private var kindTag: some View {
        CardKindTag(text: cardKindLabel(for: item))
            .accessibilityIdentifier("card.typeChip")
    }

    @ViewBuilder private func enrichmentLine(status: String?) -> some View {
        if status == "pending" {
            StashStatusLine(text: busyText, busy: true)
                .accessibilityIdentifier("card.enrichmentStatus")
        } else if status == "partial" {
            StashStatusLine(text: "some info unavailable", busy: false)
                .accessibilityIdentifier("card.enrichmentStatus")
        }
    }

    private var busyText: String {
        if item.type == .document, mimeExtensionLabel(item.mimeType) == "PDF" { return "reading the pdf…" }
        switch item.type {
        case .image: return "reading the picture…"
        case .audio, .video: return "transcribing…"
        default: return "gathering more info…"
        }
    }

    private var hasHero: Bool {
        switch item.type {
        case .link, .image, .video, .document, .audio: true
        case .text, .collection, .unknown: false
        }
    }

    @ViewBuilder private var heroZone: some View {
        switch item.type {
        case .link: LinkHeroZone(item: item)
        case .image: ImageHeroZone(item: item)
        case .video: VideoHeroZone(item: item)
        case .audio: AudioCardPlate(item: item)
        case .document:
            FilePlate(kind: .document, fileName: item.attributes.media?.fileName,
                      factsLine: factsLine(mime: item.mimeType, size: item.fileSize))
        case .text, .collection, .unknown: EmptyView()
        }
    }

    @ViewBuilder private var contentSection: some View {
        if item.type == .collection {
            collectionBody
        } else {
            if !descriptionPlain.isEmpty, item.type != .text || contentPlain.isEmpty {
                Text(descriptionPlain)
                    .stashFont(.secondary)
                    .foregroundStyle(StashColor.muted)
                    .lineLimit(previewLineLimit(3))
                    .fixedSize(horizontal: false, vertical: true)
            }
            CardNoteView(item: item)
        }
        if let note = item.supplementalNote, !note.isEmpty, item.isPublic {
            Text(note)
                .stashFont(.secondaryItalic)
                .foregroundStyle(StashColor.ink)
                .lineLimit(previewLineLimit(2))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(StashColor.white)
                .overlay(Rectangle().strokeBorder(StashColor.ink, lineWidth: 1))
                .compositingGroup()
                .shadow(color: StashColor.ink, radius: 0, x: 2, y: 2)
                .accessibilityLabel("Sticky note on your public feed: \(note)")
        }
    }

    private var collectionBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !contentPlain.isEmpty {
                Text(renderTipTap(item.content)).stashFont(.secondary).lineLimit(previewLineLimit(6))
                    .fixedSize(horizontal: false, vertical: true)
            } else if !descriptionPlain.isEmpty {
                Text(descriptionPlain).stashFont(.secondary).foregroundStyle(StashColor.muted)
                    .lineLimit(previewLineLimit(2)).fixedSize(horizontal: false, vertical: true)
            }
            CollectionStrip(itemId: item.id) { collectionCount = $0 }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(StashColor.lineSoft).frame(height: 1)
            Text(metadata)
                .stashFont(item.type == .link ? .code(.caption2) : .machine)
                .foregroundStyle(item.type == .link ? StashColor.ink : StashColor.muted)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
            if let label = item.attributes.location?.label, !label.isEmpty {
                locationBadge(label)
            }
            Text(Self.dateLabel(item.createdAt))
                .stashFont(.machine)
                .foregroundStyle(StashColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }

    private var metadata: String {
        if item.type == .link { return domainOf(item.url) }
        if item.type == .text { return "note" }
        if item.type == .collection {
            return collectionCount.map { "\($0) item\($0 == 1 ? "" : "s")" } ?? "multi-part"
        }
        let facts = factsLine(mime: item.mimeType, size: item.fileSize)
        let duration = formatDurationChip(item.attributes.media?.durationS)
        let result = [facts, duration].compactMap { $0 }.joined(separator: " · ")
        return result.isEmpty ? cardKindLabel(for: item) : result
    }

    private func locationBadge(_ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Image(systemName: "mappin").imageScale(.small)
            Text(label).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
        }
        .stashFont(.machine)
        .foregroundStyle(StashColor.muted)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("posted from \(label)")
        .accessibilityIdentifier("card.location")
    }

    private static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static let fullDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d yyyy"
        return formatter
    }()

    private static func dateLabel(_ date: Date) -> String {
        let sameYear = Calendar.current.component(.year, from: date) == Calendar.current.component(.year, from: .now)
        return (sameYear ? shortDate : fullDate).string(from: date).lowercased()
    }

    private var descriptionPlain: String { plainText(item.description) }
    private var contentPlain: String { plainText(item.content) }
    private func plainText(_ raw: String?) -> String {
        String(renderTipTap(raw).characters).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The person's own words stay italic Montreal, with the web app's simple ink annotation rule.
struct CardNoteView: View {
    let item: Item
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var preview: String {
        String(renderTipTap(item.content).characters).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        if !preview.isEmpty {
            Text(preview)
                .stashFont(.secondaryItalic)
                .foregroundStyle(StashColor.ink.opacity(0.8))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 10 : 5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)
                .padding(.vertical, 3)
                .overlay(alignment: .leading) { Rectangle().fill(StashColor.ink).frame(width: 2) }
                .accessibilityIdentifier("card.note")
        }
    }
}

/// Touch feedback changes the edge only. Its label keeps the exact card-sized hit area.
struct LibraryCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.overlay {
            RoundedRectangle(cornerRadius: StashRadius.object)
                .strokeBorder(configuration.isPressed ? StashColor.ink : .clear, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }
}
