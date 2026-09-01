import SwiftUI
import UIKit
import StashKit

/// Object-zone renderers for the card system (mirrors web `CardHero.tsx`). Portrait/contained
/// media never crops — it's centered over a blurred self-backdrop; landscape imagery covers the
/// standard hero; metadata-poor links get an honest favicon plate instead of a broken image
/// (`RepoPlate`/`FaviconPlate`/`FilePlate` live in `CardPlates.swift` — split out to keep both
/// files close to the anatomy's own ~120-line-per-file budget). Every populated zone is pinned
/// to exactly one of the two heights in `CardHeroHeight` — the anatomy's own opening rule,
/// applied uniformly (the web's plates are content-hugging; the grid's row-pairing needs a
/// fixed hero height per card instead).

// MARK: - Tall / standard image treatments (shared by link covers and the `image` type)

/// Portrait media / tall link covers (video, book): contained and centered over a blurred,
/// dimmed copy of itself so there's no dead space either side. Carries `card.hero.tall` —
/// Task 9's smoke queries it as one of two acceptable outcomes for the video-link fixture.
struct TallContainedImage: View {
    let image: Image

    var body: some View {
        // The imagery lives in an `.overlay` of a fixed-height clear base rather than as the
        // zone's own content: an overlay never participates in layout negotiation, so a
        // `.fill`-scaled image can't inflate the zone (and with it the whole card) past the
        // grid column's width — the exact blowout the two-up grid shipped with.
        Color.black
            .frame(maxWidth: .infinity, minHeight: CardHeroHeight.tall, maxHeight: CardHeroHeight.tall)
            .overlay {
                ZStack {
                    image.resizable().aspectRatio(contentMode: .fill)
                        .scaleEffect(1.25)
                        .blur(radius: 18)
                        .opacity(0.4)
                    image.resizable().aspectRatio(contentMode: .fit)
                }
            }
            .clipped()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("card.hero.tall")
    }
}

/// Landscape imagery / any non-tall link flavor with a usable image: fills the standard hero.
struct StandardCoverImage: View {
    let image: Image

    var body: some View {
        // Same overlay-over-fixed-base shape as `TallContainedImage` (and for the same reason):
        // the cover image must never be able to widen the card beyond its grid column.
        Color(.tertiarySystemFill)
            .frame(maxWidth: .infinity, minHeight: CardHeroHeight.standard, maxHeight: CardHeroHeight.standard)
            .overlay { image.resizable().aspectRatio(contentMode: .fill) }
            .clipped()
    }
}

// MARK: - Type/flavor zones

/// Link object zone: dispatches on `attributes.link.flavor` (repo/video/book/other), matching
/// `ContentItemHeader.tsx`'s link branch. A link never renders broken or blank — no usable
/// image (nil `thumbnailURL`, or a failed load) always resolves to the favicon plate.
struct LinkHeroZone: View {
    let item: Item
    @State private var imageFailed = false

    private var flavor: String { item.attributes.link?.flavor ?? "generic" }
    private var tall: Bool { flavor == "video" || flavor == "book" }
    private var zoneHeight: CGFloat { tall ? CardHeroHeight.tall : CardHeroHeight.standard }

    var body: some View {
        if flavor == "repo" {
            RepoPlate(url: item.url, description: item.description)
        } else if let url = item.thumbnailURL, !imageFailed {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    coveredImage(image)
                case .failure:
                    // Can't flip `imageFailed` mid-body-evaluation; defer to the next tick so
                    // the favicon-plate fallback renders on the following pass instead.
                    Color.clear.frame(height: zoneHeight).onAppear { imageFailed = true }
                default:
                    Color(.tertiarySystemFill).frame(height: zoneHeight)
                }
            }
        } else {
            FaviconPlate(url: item.url)
        }
    }

    @ViewBuilder private func coveredImage(_ image: Image) -> some View {
        if tall {
            TallContainedImage(image: image)
                .overlay { if flavor == "video" { PlayIconBadge() } }
                .overlay(alignment: .bottomLeading) { DomainPill(text: domainOf(item.url)).padding(10) }
        } else {
            StandardCoverImage(image: image)
        }
    }
}

/// Native `image`-type object zone: probes the real pixel aspect ratio on load
/// (`isPortraitAspect`) to choose contained-tall vs cover-standard — SwiftUI's `Image` has no
/// intrinsic-size accessor, so this fetches+decodes via `UIImage` the way the web reads
/// `naturalWidth`/`naturalHeight` from `onLoad`. A failed/missing load falls back to the file
/// plate — a captured image never renders broken.
struct ImageHeroZone: View {
    let item: Item
    @State private var uiImage: UIImage?
    @State private var failed = false

    private var facts: String? { factsLine(mime: item.mimeType, size: item.fileSize) }

    var body: some View {
        Group {
            if let uiImage {
                if isPortraitAspect(width: uiImage.size.width, height: uiImage.size.height) {
                    TallContainedImage(image: Image(uiImage: uiImage))
                } else {
                    StandardCoverImage(image: Image(uiImage: uiImage))
                }
            } else if failed || item.thumbnailURL == nil {
                FilePlate(kind: .image, fileName: item.attributes.media?.fileName, factsLine: facts)
            } else {
                Color(.tertiarySystemFill).frame(height: CardHeroHeight.standard)
            }
        }
        .task(id: item.thumbnailURL) { await load() }
    }

    private func load() async {
        guard let url = item.thumbnailURL else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let decoded = UIImage(data: data) else { failed = true; return }
            uiImage = decoded
        } catch {
            failed = true
        }
    }
}

/// Native `video`-type object zone: a thumbnail zone with the duration badge bottom-trailing.
/// No frame-extraction from the video file itself yet (AVAssetImageGenerator is a heavier lift
/// with no fixture to verify it against this task — `thumbnailURL` for a `.video` item points at
/// the video file, which `AsyncImage` can't decode as a still) — an honest dark plate + duration
/// badge stands in, same spirit as the other plates.
struct VideoHeroZone: View {
    let item: Item

    var body: some View {
        ZStack {
            Color.black
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, minHeight: CardHeroHeight.standard, maxHeight: CardHeroHeight.standard)
        .clipped()
        .overlay(alignment: .bottomTrailing) {
            if let duration = formatDurationChip(item.attributes.media?.durationS) {
                Text(duration)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
                    .padding(8)
            }
        }
    }
}

// MARK: - Link-cover decorations

private struct PlayIconBadge: View {
    var body: some View {
        Image(systemName: "play.fill")
            .foregroundStyle(.white)
            .padding(14)
            .background(Color.black.opacity(0.5), in: Circle())
    }
}

private struct DomainPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.6), in: Capsule())
    }
}
