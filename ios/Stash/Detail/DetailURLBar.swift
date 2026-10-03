import SwiftUI
import StashKit
import UIKit

/// Hairline link row — port of the web's `EditItemLinkSection.tsx`: favicon (Google's favicon
/// service, `faviconURL(for:)`) · mono URL · trailing external-link icon that opens the URL.
/// Replaces the old system-blue "Open Link" button. Link items only.
///
/// Plan 16 (HIG + accessibility):
/// - The URL is `mono(.footnote)` and scales. At the standard text sizes it keeps its one line,
///   shortened in the MIDDLE (the domain and the end of the path stay readable), and the full URL
///   is always one long press away: the context menu previews it whole, wrapped, with Copy link.
///   VoiceOver reads the whole URL either way. At the accessibility sizes one line would leave a
///   few characters, so it wraps — but to three lines at most, still shortened in the middle (2b
///   fix wave: the whole address took about 8 lines of 33 pt mono at AX3, ~300 pt of the sheet),
///   and without its scheme, so the host starts line 1 (`displayedURL`). The long-press preview
///   breaks the URL after "/", "." and "-", never mid-word with a hyphen (`breakableURL`).
/// - "Open link" takes taps across 44×44 pt and names itself for VoiceOver and the Large Content
///   Viewer; its glyph is `muted` (`faint`, 2.79:1, is decorative-only). It's a `Button` that
///   opens the URL (`openURL`, what a `Link` does): a `Link` keeps its 20×18 pt glyph as its
///   target even with the 44 pt overhang on its label (measured — Xcode's audit still flagged it),
///   while a button takes the overhang (`.stashPlain`).
struct DetailURLBar: View {
    let urlString: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL

    private var url: URL? { URL(string: urlString) }

    /// What the bar shows: the whole URL at the standard sizes. At the accessibility sizes it drops
    /// the scheme (2bf review m3), so the host starts line 1 instead of "https://" filling it. The
    /// three lines can then carry the host and the path's end. VoiceOver, Copy link and the long
    /// press keep the whole URL.
    private var displayedURL: String {
        guard dynamicTypeSize.isAccessibilitySize, let separator = urlString.range(of: "://") else {
            return urlString
        }
        // Only a real scheme (RFC 3986: a letter, then letters, digits, "+", "-", "."), never a
        // "://" further into a scheme-less string.
        let scheme = urlString[..<separator.lowerBound]
        guard let first = scheme.first, first.isASCII, first.isLetter,
              scheme.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+-.".contains($0)) }) else {
            return urlString
        }
        return String(urlString[separator.upperBound...])
    }

    /// The long-press preview's text: the URL with a zero-width break opportunity after each "/",
    /// "." and "-" (2bf review m4). So the wrap breaks there rather than hyphenating a word: AX3
    /// showed "reading.exam-" / "ple.com/", a hyphen the URL doesn't have. Display only; Copy link
    /// and VoiceOver use `urlString`.
    private var breakableURL: String {
        var out = ""
        for character in urlString {
            out.append(character)
            if character == "/" || character == "." || character == "-" { out.append("\u{200B}") }
        }
        return out
    }

    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: faviconURL(for: urlString)) { phase in
                if case .success(let image) = phase {
                    image.resizable()
                } else {
                    Color.clear
                }
            }
            .frame(width: 16, height: 16)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .accessibilityHidden(true)

            Text(displayedURL)
                .stashFont(.mono(.footnote))
                .foregroundStyle(StashColor.muted)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                // VoiceOver reads the whole URL, scheme included, at every size.
                .accessibilityLabel(urlString)
                .accessibilityIdentifier("detail.urlText")

            if let url {
                Button {
                    openURL(url)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(StashColor.muted)
                }
                .buttonStyle(.stashPlain)
                .stashIconControl("Open link", systemImage: "arrow.up.right.square")
                .accessibilityIdentifier("detail.openLink")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(StashColor.paper.opacity(0.7), in: barShape)
        .overlay(barShape.strokeBorder(StashColor.hairline, lineWidth: 1))
        // The full-URL affordance: a long press anywhere on the bar.
        .contentShape(.contextMenuPreview, barShape)
        .contextMenu {
            Button {
                UIPasteboard.general.string = urlString
            } label: {
                Label("Copy link", systemImage: "doc.on.doc")
            }
            if let url {
                Link(destination: url) {
                    Label("Open link", systemImage: "arrow.up.right.square")
                }
            }
        } preview: {
            // A definite width: the menu sizes its preview from the view's ideal size, and with only
            // a maximum width the URL's ideal is ONE line — the box came out one line tall and cut
            // the rest off (2b fix wave, measured on iOS 17.2: three lines of URL in a 47 pt box).
            Text(breakableURL)
                .stashFont(.mono(.footnote))
                .foregroundStyle(StashColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 300, alignment: .leading)
                .padding(16)
                .accessibilityLabel(urlString)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.urlBar")
    }

    private var barShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous)
    }
}
