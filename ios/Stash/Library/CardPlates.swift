import SwiftUI
import StashKit

/// The "no usable image" family of object-zone plates (split out of `CardHero.swift` to keep
/// each file close to the anatomy's own ~120-line-per-file budget): honest, content-driven
/// stand-ins instead of a broken or decorative-only hero. Every plate here is pinned to
/// `CardHeroHeight.standard` — see `CardHero.swift`'s header comment for why that's fixed even
/// though the web equivalents are content-hugging.
///
/// Plan 16: a plate's words are text people read (a repo path, a domain, a file name), so they
/// take roles and scale; the plate is `CardHeroHeight.standard` tall at least and grows when its
/// text needs more room (a fixed height would clip it at the larger sizes). Tiles and glyphs
/// stay art (`StashType.decorative`). Each plate is one VoiceOver element with its own label.

/// GitHub/GitLab repos: the repo path IS the imagery. DESIGN.md's type-spectrum table gives repo
/// its own row — `plate #0d1117` (`StashColor.repoPlate`, Task 0) — with the "owner" segment of
/// the path reading `StashColor.repoOwner` and the rest (slash + repo name) reading the row's
/// mono `#e6edf3` (`StashColor.typeText(.repo)`), a color split web's own `RepoPlate.tsx` doesn't
/// make yet (uniform white/90 + a dimmed slash) — DESIGN.md wins per its own "Per-surface notes".
struct RepoPlate: View {
    let url: String?
    let description: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var parsed: (owner: String, repo: String)? { repoPath(url) }
    private var pathLabel: String {
        if let repo = parsed { return "\(repo.owner)/\(repo.repo)" }
        return domainOf(url)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .foregroundStyle(StashColor.typeText(.repo))
                // Tabular mono for the repo path itself — DESIGN.md "repo | plate ... mono
                // #e6edf3, owner #8b7bd8", the same sanctioned system-monospace exception as
                // elsewhere. `Text` concatenation (`+`) keeps each segment's own color inside one
                // line-wrapping unit, unlike three sibling `Text` views in an `HStack`.
                Group {
                    if let parsed {
                        Text(parsed.owner).foregroundColor(StashColor.repoOwner)
                            + Text("/").foregroundColor(StashColor.typeText(.repo).opacity(0.5))
                            + Text(parsed.repo).foregroundColor(StashColor.typeText(.repo))
                    } else {
                        Text(pathLabel).foregroundColor(StashColor.typeText(.repo))
                    }
                }
                .stashFont(.mono(.subheadline))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
            }
            if let description, !description.isEmpty {
                Text(description)
                    .stashFont(.secondary)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: CardHeroHeight.standard, alignment: .leading)
        .background(StashColor.repoPlate)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pathLabel)
        .accessibilityIdentifier("card.repoplate")
    }
}

/// Metadata-poor links: favicon-style plate, honest and never broken.
struct FaviconPlate: View {
    let url: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var domain: String { domainOf(url) }
    private var letter: String { domain.first.map { String($0).uppercased() } ?? "?" }

    var body: some View {
        HStack(spacing: 12) {
            // The monogram tile is art: a fixed letter in a fixed tile (the plate's label names the
            // domain).
            Text(letter)
                .font(StashType.decorative(.semibold, size: 17))
                .foregroundStyle(Color.cardVioletAccent)
                .frame(width: 48, height: 48)
                .background(Color.cardVioletTint, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(domain.isEmpty ? "link" : domain)
                    .stashFont(.metaMedium)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                Text("preview limited · saved anyway")
                    .stashFont(.meta)
                    .foregroundStyle(StashColor.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: CardHeroHeight.standard)
        .background(Color(.tertiarySystemFill).opacity(0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(domain.isEmpty ? "link" : domain) — preview limited, saved anyway")
        .accessibilityIdentifier("card.faviconplate")
    }
}

/// Documents and imageless media: a file plate instead of a decorative/broken hero. `.document`
/// and `.screenshot` read DESIGN.md's type-spectrum tint (Task 0's `StashColor.typeField`/
/// `typeText`) on the icon tile — `.image` (a genuinely-imageless regular photo, not a type the
/// spectrum table tints) keeps the pre-existing violet stand-in. `.screenshot` only reaches this
/// plate on the rare fallback path (no thumbnail at all) — DESIGN.md's per-type hero table has
/// screenshots render full-bleed real imagery same as any photo; the tinted chip (`CardChips.swift`
/// `typeChip(for:)`) carries the identity in the common case.
struct FilePlate: View {
    enum Kind { case image, document, screenshot }

    let kind: Kind
    let fileName: String?
    let factsLine: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var tint: Color {
        switch kind {
        case .image: return .cardVioletAccent
        case .document: return StashColor.typeText(.document)
        case .screenshot: return StashColor.typeText(.screenshot)
        }
    }
    private var tintBg: Color {
        switch kind {
        case .image: return .cardVioletTint
        case .document: return StashColor.typeField(.document)
        case .screenshot: return StashColor.typeField(.screenshot)
        }
    }
    private var label: String {
        switch kind {
        case .image: return fileName ?? "Image"
        case .document: return fileName ?? "Document"
        case .screenshot: return fileName ?? "Screenshot"
        }
    }
    private var iconName: String {
        switch kind {
        case .image: return "photo"
        case .document: return "doc.text"
        case .screenshot: return "viewfinder"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // The icon tile is art: a fixed glyph in a fixed tile.
            Image(systemName: iconName)
                .font(StashType.decorative(.book, size: 17))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tintBg, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .stashFont(fileName != nil ? .mono(.caption) : .metaMedium)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    .truncationMode(.middle)
                if let factsLine, !factsLine.isEmpty {
                    Text(factsLine).stashFont(.meta).foregroundStyle(StashColor.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: CardHeroHeight.standard)
        .background(Color(.tertiarySystemFill).opacity(0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([label, factsLine].compactMap { $0 }.joined(separator: " "))
        .accessibilityIdentifier("card.fileplate")
    }
}
