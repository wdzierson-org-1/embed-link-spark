import SwiftUI
import StashKit

/// A single card in the library grid: thumbnail, type + title, description, relative date.
/// Shows a shimmering redacted overlay while a document is still being processed, and a
/// yellow sticky-note corner badge when the item carries a public supplemental note.
struct ItemCardView: View {
    let item: Item

    @State private var shimmerPhase: CGFloat = -1

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            thumbnail
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: typeIcon)
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            if let description = item.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Text(item.createdAt, format: .relative(presentation: .named))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .topTrailing) { stickyBadge }
        .redacted(reason: item.isProcessingDocument ? .placeholder : [])
        .overlay { if item.isProcessingDocument { shimmer } }
    }

    private var title: String {
        let trimmed = item.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    @ViewBuilder private var thumbnail: some View {
        if let url = item.thumbnailURL {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color(.tertiarySystemFill)
                }
            }
            .aspectRatio(4 / 3, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .clipped()
        }
    }

    @ViewBuilder private var stickyBadge: some View {
        if let note = item.supplementalNote, !note.isEmpty, item.isPublic {
            Image(systemName: "note.text")
                .font(.caption2)
                .foregroundStyle(.black.opacity(0.7))
                .padding(5)
                .background(Color.yellow, in: RoundedRectangle(cornerRadius: 4))
                .rotationEffect(.degrees(6))
                .padding(6)
        }
    }

    /// Simple sweeping-gradient shimmer over the redacted placeholder while processing.
    private var shimmer: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, .white.opacity(0.55), .clear],
                            startPoint: .leading, endPoint: .trailing)
                .frame(width: geo.size.width * 0.6)
                .offset(x: shimmerPhase * geo.size.width)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                shimmerPhase = 1.6
            }
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
