import SwiftUI
import StashKit

/// Horizontal row of TypeFilter chips. Writing `store.typeFilter` is observed by
/// `LibraryView`'s `.onChange`, which triggers the server-side refetch.
struct TypeChipRow: View {
    let store: ItemStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TypeFilter.allCases, id: \.self) { filter in
                    let isSelected = store.typeFilter == filter
                    Button {
                        store.typeFilter = filter
                    } label: {
                        Text(filter.label)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground),
                                        in: Capsule())
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                    }
                    .accessibilityIdentifier("library.chip.\(filter.rawValue)")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}
