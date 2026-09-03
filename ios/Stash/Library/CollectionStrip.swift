import SwiftUI
import StashKit

/// Read-only strip of a legacy multi-part item's attachments (frozen design, mirrors web
/// `CollectionAttachmentStrip.tsx`): up to 4 tiles plus a "+N" overflow tile. The legacy
/// `collection` type predates the single-object model (never created going forward — Global
/// Constraints) so there's no shared in-memory attachment list to reuse the way the web's
/// `ContentGrid` prefetch does; this fetches `item_attachments` itself on appear. Reused
/// read-only by Task 8's detail-sheet "Attachments" section.
struct CollectionStrip: View {
    let itemId: UUID
    /// Reports the fetched count back up so the card footer's "N items" badge (which owns no
    /// fetch of its own) can read it once it lands.
    var onCountChange: (Int) -> Void = { _ in }

    @State private var attachments: [CollectionAttachment] = []
    private let maxTiles = 4

    private var shown: [CollectionAttachment] { Array(attachments.prefix(maxTiles)) }
    private var overflow: Int { max(0, attachments.count - maxTiles) }

    var body: some View {
        Group {
            if !attachments.isEmpty {
                HStack(spacing: 8) {
                    ForEach(shown) { AttachmentTile(attachment: $0) }
                    if overflow > 0 { OverflowTile(count: overflow) }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let data = try? await StashClient.shared.from("item_attachments")
            .select("id,type,title,url,file_path")
            .eq("item_id", value: itemId.uuidString)
            .order("created_at", ascending: true)
            .execute().data,
              let decoded = try? JSONDecoder().decode([CollectionAttachment].self, from: data)
        else { return }
        attachments = decoded
        onCountChange(decoded.count)
    }
}

private struct CollectionAttachment: Codable, Identifiable {
    let id: UUID
    let type: String
    let title: String?
    let url: String?
    let filePath: String?

    enum CodingKeys: String, CodingKey {
        case id, type, title, url
        case filePath = "file_path"
    }
}

private struct AttachmentTile: View {
    let attachment: CollectionAttachment

    var body: some View {
        Group {
            if attachment.type == "image", let path = attachment.filePath {
                AsyncImage(url: StashConfig.publicStorageURL(for: path)) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        iconTile
                    }
                }
            } else {
                iconTile
            }
        }
        .frame(width: 72, height: 72)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var iconTile: some View {
        VStack(spacing: 4) {
            Image(systemName: iconName).foregroundStyle(StashColor.muted)
            Text(attachment.title ?? attachment.type)
                .font(StashType.regular(size: 9))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(StashColor.muted)
        }
        .padding(4)
    }

    private var iconName: String {
        switch attachment.type {
        case "audio": "waveform"
        case "video": "video"
        case "link": "link"
        default: "doc.text"
        }
    }
}

private struct OverflowTile: View {
    let count: Int

    var body: some View {
        Text("+\(count)")
            .font(StashType.bodyMedium(13))
            .foregroundStyle(StashColor.muted)
            .frame(width: 56, height: 72)
            .background(Color(.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    // No legacy `collection` fixture exists in the account this plan verifies against (Global
    // Constraints: the type predates the single-object model and is never created going
    // forward) — this stubbed preview is the only visual check available for this task; see
    // task-7-report.md for that verification-boundary disclosure.
    CollectionStrip(itemId: UUID())
        .padding()
}
