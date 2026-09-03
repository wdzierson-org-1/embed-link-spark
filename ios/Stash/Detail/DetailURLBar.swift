import SwiftUI
import StashKit

/// Hairline link row — port of the web's `EditItemLinkSection.tsx`: favicon (Google's favicon
/// service, `faviconURL(for:)`) · mono URL, single-line, truncated · trailing external-link icon
/// that opens the URL. Replaces the old system-blue "Open Link" button. Link items only.
struct DetailURLBar: View {
    let urlString: String

    private var url: URL? { URL(string: urlString) }

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

            Text(urlString)
                .font(StashType.mono(12.5))
                .foregroundStyle(StashColor.muted)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let url {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(StashColor.faint)
                }
                .accessibilityLabel("Open link")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(StashColor.paper.opacity(0.7), in: RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous)
                .strokeBorder(StashColor.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.urlBar")
    }
}
