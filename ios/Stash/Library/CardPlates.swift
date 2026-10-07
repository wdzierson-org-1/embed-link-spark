import SwiftUI
import StashKit

/// A repository's identity is its imagery: one ink plate, a pixel prompt, and human prose.
struct RepoPlate: View {
    let url: String?
    let description: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var pathLabel: String {
        if let path = repoPath(url) { return "\(path.owner)/\(path.repo)" }
        return domainOf(url)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            (Text("> ").foregroundColor(StashColor.spotOnInk) + Text(pathLabel).foregroundColor(.white))
                .stashFont(.code(.callout))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
            if let description, !description.isEmpty {
                Text(description)
                    .stashFont(.secondary)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 48)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, minHeight: CardHeroHeight.standard, alignment: .leading)
        .background(StashColor.ink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pathLabel)
        .accessibilityIdentifier("card.repoplate")
    }
}

/// No request is made for a favicon in the library. The domain and kind are enough to identify
/// a save without disclosing every saved domain to another service on each load.
struct FaviconPlate: View {
    let url: String?
    var kind = "page"
    var reading = false

    private var domain: String { domainOf(url).isEmpty ? "link" : domainOf(url) }

    var body: some View {
        VStack(spacing: 12) {
            CardPixelGlyph(kind: kind)
                .frame(width: 42, height: 42)
            Text(domain)
                .stashFont(.code(.caption2))
                .foregroundStyle(StashColor.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(StashColor.ink)
        }
        .padding(.horizontal, 12)
        .padding(.top, 40)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, minHeight: CardHeroHeight.standard)
        .background {
            ZStack {
                StashColor.fill
                StashDotGrid(spacing: 6, opacity: 0.09)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading ? "\(domain), gathering more info" : "\(domain), preview limited, saved anyway")
        .accessibilityIdentifier("card.faviconplate")
    }
}

struct FilePlate: View {
    enum Kind { case image, document, screenshot }
    let kind: Kind
    let fileName: String?
    let factsLine: String?

    private var label: String {
        fileName ?? (kind == .document ? "document" : kind == .screenshot ? "screenshot" : "photo")
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            StashColor.fill
            StashDotGrid(spacing: 6, opacity: 0.09)
            if kind == .document {
                documentPage
                    .padding(.horizontal, 32)
                    .padding(.top, 48)
                    .offset(y: 10)
            } else {
                VStack(spacing: 12) {
                    CardPixelGlyph(kind: "photo").frame(width: 42, height: 42)
                    Text(label)
                        .stashFont(.code(.caption2))
                        .foregroundStyle(StashColor.white)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .padding(6)
                        .background(StashColor.ink)
                }
                .padding(.horizontal, 12)
                .padding(.top, 40)
                .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, minHeight: CardHeroHeight.standard, maxHeight: CardHeroHeight.standard)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([label, factsLine].compactMap { $0 }.joined(separator: " "))
        .accessibilityIdentifier("card.fileplate")
    }

    private var documentPage: some View {
        VStack(alignment: .leading, spacing: 7) {
            Rectangle().fill(StashColor.ink).frame(width: 24, height: 5)
                .padding(.bottom, 6)
            ForEach(0..<6) { index in
                Rectangle().fill(index == 5 ? StashColor.line : StashColor.lineSoft)
                    .frame(height: 3)
                    .padding(.trailing, index % 3 == 0 ? 16 : 0)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(StashColor.white)
        .overlay(Rectangle().strokeBorder(StashColor.line, lineWidth: 1))
        .rotationEffect(.degrees(-2.5))
        .accessibilityHidden(true)
    }
}

/// A passive audio drawing: the whole mobile card still opens the detail sheet. The microphone
/// and waveform name the media without promising a playback control that iOS does not provide.
struct AudioCardPlate: View {
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: audioSubtype(item) == .voice ? "mic.fill" : "waveform")
                    .font(StashType.decorative(.medium, size: 15))
                    .foregroundStyle(StashColor.white)
                    .frame(width: 40, height: 40)
                    .background(StashColor.ink)
                GeometryReader { geometry in
                    HStack(alignment: .center, spacing: 2) {
                        ForEach(0..<28) { index in
                            Rectangle().fill(StashColor.ink.opacity(0.45))
                                .frame(width: max(1, (geometry.size.width - 54) / 28),
                                       height: CGFloat([9, 17, 24, 13, 30, 18, 11][index % 7]))
                        }
                    }
                    .frame(height: 40)
                }
                .frame(height: 40)
            }
            .accessibilityHidden(true)
            if let duration = formatDurationChip(item.attributes.media?.durationS) {
                Text(duration).stashFont(.machine).foregroundStyle(StashColor.muted)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 48)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, minHeight: 116)
        .background(StashColor.fill)
    }
}

/// Crisp 14×14 bitmaps copied from the web app's machine/glyphs.ts. The drawing is decorative;
/// its containing plate supplies the save's spoken identity.
struct CardPixelGlyph: View {
    let kind: String

    var body: some View {
        Canvas { context, size in
            let rows = Self.glyphs[kind] ?? Self.glyphs["page"]!
            let unit = min(size.width, size.height) / 14
            var path = Path()
            for (y, row) in rows.enumerated() {
                for (x, cell) in row.enumerated() where cell == "#" {
                    path.addRect(CGRect(x: CGFloat(x) * unit, y: CGFloat(y) * unit, width: unit, height: unit))
                }
            }
            context.fill(path, with: .color(StashColor.ink))
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private static let glyphs: [String: [String]] = [
        "page": ["##############", "#.#.#........#", "##############", "#............#", "#.#######....#", "#............#", "#.##########.#", "#.##########.#", "#.##########.#", "#............#", "#.#########..#", "#.#######....#", "#............#", "##############"],
        "article": ["..##########..", "..#........#..", "..#.######.#..", "..#.######.#..", "..#........#..", "..#.######.#..", "..#........#..", "..#.######.#..", "..#........#..", "..#.####...#..", "..#........#..", "..#.######.#..", "..#........#..", "..##########.."],
        "video": ["..............", "..............", ".############.", "##############", "#####.########", "#####..#######", "#####...######", "#####....#####", "#####...######", "#####..#######", "#####.########", "##############", ".############.", ".............."],
        "book": ["..##########..", "..##.......#..", "..##.#####.#..", "..##.......#..", "..##.####..#..", "..##.......#..", "..##.......#..", "..##...#...#..", "..##..###..#..", "..##.#####.#..", "..##.......#..", "..##########..", "...#########..", ".............."],
        "social": ["..............", "..............", ".############.", "#............#", "#.##########.#", "#............#", "#.#######....#", "#............#", ".##.#########.", "...##.........", "...#..........", "..............", "..............", ".............."],
        "photo": ["..............", "##############", "#............#", "#.........##.#", "#.........##.#", "#............#", "#....#.......#", "#...###......#", "#..#####..#..#", "#.#######.##.#", "############.#", "#............#", "##############", ".............."]
    ]
}

/// The web's quiet mosaic while a real picture is downloading. No perpetual idle animation.
struct CardImageMosaic: View {
    var height: CGFloat = CardHeroHeight.standard

    var body: some View {
        Canvas { context, size in
            let colors = [StashColor.fill, StashColor.lineSoft, StashColor.line, StashColor.paper]
            for y in stride(from: 0, to: Int(size.height), by: 8) {
                for x in stride(from: 0, to: Int(size.width), by: 8) {
                    let shade = ((x / 8) * 13 + (y / 8) * 7) % colors.count
                    context.fill(Path(CGRect(x: CGFloat(x), y: CGFloat(y), width: 8, height: 8)), with: .color(colors[shade]))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
