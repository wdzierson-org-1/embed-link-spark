import SwiftUI

/// Shared pill-tab control — the same visual pattern `SignInView`'s Sign in/Sign up tabs
/// established (a `wash` capsule track; the selected tab floats a `paper` capsule with a hairline
/// border and a soft shadow over it). Extracted here (rather than duplicated) so any tab-style
/// selector across the app — the detail sheet's content tabs (Task 6) included — draws from one
/// implementation.
///
/// Plan 16 (HIG + accessibility): labels are the `secondaryMedium` role (Medium 15, `.subheadline`,
/// Bold Text aware). Segmented chrome, like `UISegmentedControl`: they grow with Dynamic Type up
/// to xxxLarge and stop there — at the accessibility sizes a long press shows the tab's label in
/// the Large Content Viewer. Content-sized tabs that outgrow the width scroll sideways instead of
/// squeezing or truncating. Each tab takes taps across its whole pill (it used to be just the word
/// while unselected) and at least 44 pt of height; its accessibility frame is the pill too, and
/// the selected tab carries VoiceOver's Selected trait (fix wave, I4).
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
        HStack(spacing: 4) {
            ForEach(items, id: \.tab) { item in
                button(item)
            }
        }
        .padding(4)
        .background(StashColor.wash, in: Capsule())
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
                .foregroundStyle(selected ? StashColor.ink : StashColor.muted)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background {
                    if selected {
                        Capsule()
                            .fill(StashColor.paper)
                            .overlay(Capsule().strokeBorder(StashColor.hairline, lineWidth: 1))
                            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                    }
                }
                .contentShape(.accessibility, Capsule())
                .stashMinimumHitTarget()
        }
        .buttonStyle(.plain)
        // VoiceOver says which tab is showing ("Summary, selected") — the paper capsule alone is
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
