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
///
/// Plan 15 (Task 3) — hit testing: a `.fill`-scaled image (and the 1.25× blurred backdrop) is
/// larger than its zone. `.clipped()` only clips DRAWING, not hit testing, and each card is drawn
/// above the one before it, so the overflow of card N+1's hero used to swallow taps aimed at the
/// bottom of card N (Will: "when tapping the bottom of the first item in the list, it often chooses
/// the second item"). The imagery is therefore `.allowsHitTesting(false)` — the zone's fixed-size
/// base carries the card's taps — and `LibraryView` also gives each card button an exact
/// `contentShape`. Images load through `ImagePipeline` (memory + disk cache, downsampled decode).

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
                .allowsHitTesting(false)
            }
            .clipped()
            // One leaf element sized to the zone itself (not the overflowing backdrop), so the
            // card's accessibility frame matches what's drawn.
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("card.hero.tall")
    }
}

/// Landscape imagery / any non-tall link flavor with a usable image: fills the standard hero.
/// Carries `card.hero.cover` (plan 15) — only present once the image has actually loaded.
struct StandardCoverImage: View {
    let image: Image

    var body: some View {
        // Same overlay-over-fixed-base shape as `TallContainedImage` (and for the same reason):
        // the cover image must never be able to widen the card beyond its grid column.
        Color(.tertiarySystemFill)
            .frame(maxWidth: .infinity, minHeight: CardHeroHeight.standard, maxHeight: CardHeroHeight.standard)
            .overlay { image.resizable().aspectRatio(contentMode: .fill).allowsHitTesting(false) }
            .clipped()
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("card.hero.cover")
    }
}

// MARK: - Sizing (shared with the app-scope hero prefetch)

/// The exact `ImageRequest` a card's hero makes — computed identically by the hero views and by
/// `MainTabView`'s first-page prefetch, so a prefetched image is a memory hit on first draw.
@MainActor
enum CardHeroSizing {
    /// Card width for the current window: `LibraryView.grid`'s 16pt side padding, one column on
    /// phones (two where the width class is regular, 8pt apart).
    static func cardWidth(regularWidth: Bool) -> CGFloat {
        let columns: CGFloat = regularWidth ? 2 : 1
        return ((ScreenMetrics.windowWidth - 32 - (columns - 1) * 8) / columns).rounded(.down)
    }

    /// nil when the item's hero isn't an image (plates, repo links, video items, no thumbnail).
    static func fit(for item: Item, cardWidth: CGFloat) -> ImageFit? {
        guard item.thumbnailURL != nil else { return nil }
        let tall = CGSize(width: cardWidth, height: CardHeroHeight.tall)
        let standard = CGSize(width: cardWidth, height: CardHeroHeight.standard)
        switch item.type {
        case .link:
            let flavor = item.attributes.link?.flavor ?? "generic"
            if flavor == "repo" { return nil }
            return flavor == "video" || flavor == "book" ? .fit(tall) : .fill(standard)
        case .image:
            return .hero(portrait: tall, landscape: standard)
        default:
            return nil
        }
    }

    static func request(for item: Item, cardWidth: CGFloat, scale: CGFloat) -> ImageRequest? {
        guard let url = item.thumbnailURL, let fit = fit(for: item, cardWidth: cardWidth) else { return nil }
        return ImageRequest(url: url, fit: fit, scale: scale)
    }
}

/// Card content width for the hero views, set once by `LibraryView`.
private struct CardWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 361
}

extension EnvironmentValues {
    var cardWidth: CGFloat {
        get { self[CardWidthKey.self] }
        set { self[CardWidthKey.self] = newValue }
    }
}

// MARK: - Type/flavor zones

/// Link object zone: dispatches on `attributes.link.flavor` (repo/video/book/other), matching
/// `ContentItemHeader.tsx`'s link branch. A link never renders broken or blank — no usable
/// image (nil `thumbnailURL`, or a failed load) always resolves to the favicon plate.
struct LinkHeroZone: View {
    let item: Item
    @Environment(\.cardWidth) private var cardWidth

    private var flavor: String { item.attributes.link?.flavor ?? "generic" }
    private var tall: Bool { flavor == "video" || flavor == "book" }
    private var zoneHeight: CGFloat { tall ? CardHeroHeight.tall : CardHeroHeight.standard }

    var body: some View {
        if flavor == "repo" {
            RepoPlate(url: item.url, description: item.description)
        } else if let url = item.thumbnailURL, let fit = CardHeroSizing.fit(for: item, cardWidth: cardWidth) {
            CachedImage(url: url, fit: fit) { phase in
                switch phase {
                case .success(let image):
                    coveredImage(Image(uiImage: image))
                case .failure:
                    FaviconPlate(url: item.url)
                case .empty:
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

/// Native `image`-type object zone: the real pixel aspect ratio (known once decoded) chooses
/// contained-tall vs cover-standard (`isPortraitAspect`) — the way the web reads
/// `naturalWidth`/`naturalHeight` from `onLoad`. A failed/missing load falls back to the file
/// plate — a captured image never renders broken.
struct ImageHeroZone: View {
    let item: Item
    @Environment(\.cardWidth) private var cardWidth

    private var facts: String? { factsLine(mime: item.mimeType, size: item.fileSize) }

    var body: some View {
        if let url = item.thumbnailURL, let fit = CardHeroSizing.fit(for: item, cardWidth: cardWidth) {
            CachedImage(url: url, fit: fit) { phase in
                switch phase {
                case .success(let image):
                    if isPortraitAspect(width: image.size.width, height: image.size.height) {
                        TallContainedImage(image: Image(uiImage: image))
                    } else {
                        StandardCoverImage(image: Image(uiImage: image))
                    }
                case .failure:
                    filePlate
                case .empty:
                    Color(.tertiarySystemFill).frame(height: CardHeroHeight.standard)
                }
            }
        } else {
            filePlate
        }
    }

    /// Screenshot identity carries through even on this rare imageless-fallback path
    /// (DESIGN.md's type-spectrum "screenshot" tint) — `ItemDisplay.isScreenshot` reads
    /// `media.kind` first, then the vision title's own words.
    private var filePlate: some View {
        FilePlate(kind: ItemDisplay.isScreenshot(item) ? .screenshot : .image,
                  fileName: item.attributes.media?.fileName, factsLine: facts)
    }
}

/// Native `video`-type object zone: a thumbnail zone with the duration badge bottom-trailing.
/// No frame-extraction from the video file itself yet (AVAssetImageGenerator is a heavier lift
/// with no fixture to verify it against this task — `thumbnailURL` for a `.video` item points at
/// the video file, which an image decoder can't read as a still) — an honest dark plate + duration
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
                    .font(StashType.chip())
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
            .font(StashType.chip())
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.6), in: Capsule())
    }
}
