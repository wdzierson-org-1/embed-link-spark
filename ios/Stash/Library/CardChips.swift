import SwiftUI
import StashKit

enum CardHeroHeight {
    static let standard: CGFloat = 160
    static let tall: CGFloat = 224
}

/// The machine's square label. Kept separate from metadata, which is plain text under a rule.
struct CardKindTag: View {
    let text: String
    var inverted = false

    var body: some View {
        Text(text)
            .stashFont(.machine)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(inverted ? StashColor.ink : StashColor.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(inverted ? StashColor.white : StashColor.ink)
    }
}

struct MetaChip: View {
    var mono = false
    let text: String

    var body: some View {
        Text(text.lowercased())
            .stashFont(mono ? .code(.caption2) : .machine)
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(StashColor.muted)
    }
}

func factsLine(mime: String?, size: Int?) -> String? {
    let parts = [mimeExtensionLabel(mime), formatFileSizeChip(size)].compactMap { $0 }
    return parts.isEmpty ? nil : parts.joined(separator: " · ").lowercased()
}

func audioSubtype(_ item: Item) -> StashColor.TypeTint {
    ItemDisplay.audioKind(for: item) == .recording ? .audio : .voice
}

func isScreenshotItem(_ item: Item) -> Bool { ItemDisplay.isScreenshot(item) }

func isSpreadsheetExt(_ ext: String?) -> Bool { ext == "XLSX" || ext == "XLS" || ext == "CSV" }

/// Shared by card labels and the detail window bar; this never changes the stored item type.
func cardKindLabel(for item: Item) -> String {
    switch item.type {
    case .audio: return audioSubtype(item) == .voice ? "voice note" : "recording"
    case .document:
        let ext = mimeExtensionLabel(item.mimeType)
        return isSpreadsheetExt(ext) ? "spreadsheet" : (ext?.lowercased() ?? "document")
    case .image: return isScreenshotItem(item) ? "screenshot" : "photo"
    case .video: return "video"
    case .text: return "note"
    case .link:
        let flavor = item.attributes.link?.flavor ?? "generic"
        return ["article": "article", "video": "video", "repo": "repo", "book": "book", "social": "post"][flavor] ?? "link"
    case .collection: return "multi-part"
    case .unknown: return "save"
    }
}

func typeChip(for item: Item) -> AnyView? {
    AnyView(CardKindTag(text: cardKindLabel(for: item))
        .accessibilityIdentifier("card.typeChip"))
}
