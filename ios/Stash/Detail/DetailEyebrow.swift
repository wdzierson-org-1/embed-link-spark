import SwiftUI
import StashKit

/// The native sheet's machine bar uses the same identity, source and date as the web panel.
struct DetailEyebrow: View {
    let item: Item
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var domain: String { domainOf(item.url) }
    private var source: String {
        let date = "saved \(Self.dateFormatter.string(from: item.createdAt).lowercased())"
        return item.type == .link && !domain.isEmpty ? "\(domain) · \(date)" : date
    }

    var body: some View {
        HStack(spacing: 10) {
            Image("StashSymbol")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(StashColor.spotOnInk)
                .frame(width: 16, height: 20)
                .accessibilityHidden(true)
            Text(source)
                .stashFont(.machine)
                .foregroundStyle(StashColor.white.opacity(0.7))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(source)
        .accessibilityIdentifier("detail.eyebrow")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d yyyy"
        return formatter
    }()
}
