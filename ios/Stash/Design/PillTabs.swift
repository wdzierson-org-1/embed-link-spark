import SwiftUI

/// Source-compatible segmented control, restyled as square machine tabs. Labels remain
/// Montreal, grow through xxxLarge, and expose the Large Content Viewer at larger sizes.
/// Every tab has a real 44 pt height so its target survives a scrolling container.
struct PillTabs<Tab: Hashable>: View {
    struct Item {
        let tab: Tab
        let label: String
        /// Optional per-tab accessibility identifier; the label text itself is always the
        /// visible/default accessible name, matching `SignInView.tabButton`'s own convention.
        var identifier: String?

        init(_ tab: Tab, label: String, identifier: String? = nil) {
            self.tab = tab
            self.label = label
            self.identifier = identifier
        }
    }

    let items: [Item]
    @Binding var selection: Tab
    /// When true, tabs split the track's full width evenly (web parity: shadcn `Tabs`' `grid
    /// w-full grid-cols-2` on the sign-in card). Default `false` keeps the original content-sized
    /// behavior the detail sheet's content tabs (Summary / Original Content / Notes) rely on.
    var fillWidth: Bool = false

    var body: some View {
        Group {
            if fillWidth {
                track
            } else {
                ViewThatFits(in: .horizontal) {
                    track
                    ScrollView(.horizontal, showsIndicators: false) { track }
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var track: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.tab) { item in
                button(item)
            }
        }
        .background(StashColor.white)
        .overlay(Rectangle().strokeBorder(StashColor.line, lineWidth: 1))
    }

    private func button(_ item: Item) -> some View {
        let selected = item.tab == selection
        return Button {
            selection = item.tab
        } label: {
            Text(item.label)
                .stashFont(.secondaryMedium)
                .lineLimit(1)
                .fixedSize(horizontal: !fillWidth, vertical: true)
                .frame(maxWidth: fillWidth ? .infinity : nil)
                .foregroundStyle(selected ? StashColor.white : StashColor.muted)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(minHeight: 44)
                .background(selected ? StashColor.ink : StashColor.white)
                .contentShape(Rectangle())
                .contentShape(.accessibility, Rectangle())
                .stashMinimumHitTarget()
        }
        .buttonStyle(.plain)
        // VoiceOver says which tab is showing ("Summary, selected") — the ink field alone is
        // only visual (WCAG 4.1.2).
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityShowsLargeContentViewer { Text(item.label) }
        .modifier(OptionalAccessibilityIdentifier(identifier: item.identifier))
    }
}

/// `.accessibilityIdentifier` only when a non-nil value is supplied — lets `PillTabs` fall back
/// to the button's own label-based lookup (the pattern `testDetailSheets` already relies on for
/// tab buttons) when no explicit identifier is given.
private struct OptionalAccessibilityIdentifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}
