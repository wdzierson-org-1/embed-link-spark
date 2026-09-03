import SwiftUI

/// Shared pill-tab control — the same visual pattern `SignInView`'s Sign in/Sign up tabs
/// established (a `wash` capsule track; the selected tab floats a `paper` capsule with a hairline
/// border and a soft shadow over it). Extracted here (rather than duplicated) so any tab-style
/// selector across the app — the detail sheet's content tabs (Task 6) included — draws from one
/// implementation.
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
                .font(StashType.bodyMedium())
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
        }
        .buttonStyle(.plain)
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
