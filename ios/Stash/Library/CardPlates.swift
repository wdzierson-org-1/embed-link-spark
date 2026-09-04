import SwiftUI
import StashKit

/// The "no usable image" family of object-zone plates (split out of `CardHero.swift` to keep
/// each file close to the anatomy's own ~120-line-per-file budget): honest, content-driven
/// stand-ins instead of a broken or decorative-only hero. Every plate here is pinned to
/// `CardHeroHeight.standard` — see `CardHero.swift`'s header comment for why that's fixed even
/// though the web equivalents are content-hugging.

/// GitHub/GitLab repos: the repo path IS the imagery. DESIGN.md's type-spectrum table gives repo
/// its own row — `plate #0d1117` (`StashColor.repoPlate`, Task 0) — with the "owner" segment of
/// the path reading `StashColor.repoOwner` and the rest (slash + repo name) reading the row's
/// mono `#e6edf3` (`StashColor.typeText(.repo)`), a color split web's own `RepoPlate.tsx` doesn't
/// make yet (uniform white/90 + a dimmed slash) — DESIGN.md wins per its own "Per-surface notes".
struct RepoPlate: View {
    let url: String?
    let description: String?

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
                .font(StashType.mono(15))
                .lineLimit(1)
            }
            if let description, !description.isEmpty {
                Text(description)
                    .font(StashType.body())
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(16)
        .frame(height: CardHeroHeight.standard)
        .background(StashColor.repoPlate)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pathLabel)
        .accessibilityIdentifier("card.repoplate")
    }
}

/// Metadata-poor links: favicon-style plate, honest and never broken.
struct FaviconPlate: View {
    let url: String?

    private var domain: String { domainOf(url) }
    private var letter: String { domain.first.map { String($0).uppercased() } ?? "?" }

    var body: some View {
        HStack(spacing: 12) {
            Text(letter)
                .font(StashType.semibold(size: 17))
                .foregroundStyle(Color.cardVioletAccent)
                .frame(width: 48, height: 48)
                .background(Color.cardVioletTint, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text(domain.isEmpty ? "link" : domain)
                    .font(StashType.bodyMedium(13))
                    .lineLimit(1)
                Text("preview limited · saved anyway")
                    .font(StashType.regular(size: 11))
                    .foregroundStyle(StashColor.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .frame(height: CardHeroHeight.standard)
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
            Image(systemName: iconName)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tintBg, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(fileName != nil ? StashType.mono(12) : StashType.bodyMedium(13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let factsLine, !factsLine.isEmpty {
                    Text(factsLine).font(StashType.regular(size: 11)).foregroundStyle(StashColor.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .frame(height: CardHeroHeight.standard)
        .background(Color(.tertiarySystemFill).opacity(0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([label, factsLine].compactMap { $0 }.joined(separator: " "))
        .accessibilityIdentifier("card.fileplate")
    }
}
