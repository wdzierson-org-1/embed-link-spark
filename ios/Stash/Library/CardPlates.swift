import SwiftUI
import StashKit

/// The "no usable image" family of object-zone plates (split out of `CardHero.swift` to keep
/// each file close to the anatomy's own ~120-line-per-file budget): honest, content-driven
/// stand-ins instead of a broken or decorative-only hero. Every plate here is pinned to
/// `CardHeroHeight.standard` — see `CardHero.swift`'s header comment for why that's fixed even
/// though the web equivalents are content-hugging.

/// GitHub/GitLab repos: the repo path IS the imagery.
struct RepoPlate: View {
    let url: String?
    let description: String?

    private var pathLabel: String {
        if let repo = repoPath(url) { return "\(repo.owner)/\(repo.repo)" }
        return domainOf(url)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                // Tabular mono for the repo path itself — DESIGN.md "repo | plate ... mono
                // #e6edf3", the same sanctioned system-monospace exception as elsewhere.
                Text(pathLabel).font(StashType.mono(15)).lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.9))
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
        .background(Color(red: 0.051, green: 0.067, blue: 0.09))
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

/// Documents and imageless media: a file plate instead of a decorative/broken hero.
struct FilePlate: View {
    enum Kind { case image, document }

    let kind: Kind
    let fileName: String?
    let factsLine: String?

    private var tint: Color { kind == .image ? .cardVioletAccent : .cardRedAccent }
    private var tintBg: Color { kind == .image ? .cardVioletTint : .cardRedTint }
    private var label: String { fileName ?? (kind == .image ? "Image" : "Document") }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: kind == .image ? "photo" : "doc.text")
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
