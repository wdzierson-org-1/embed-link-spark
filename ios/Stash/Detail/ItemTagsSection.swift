import SwiftUI
import StashKit
import Supabase

/// Tags manager (Task 9, port of the web's `ItemTagsManager.tsx`): current tags as removable
/// chips, a plain add-on-return input, and AI-suggested tags below (via `get-relevant-tags`)
/// filtered against what's already applied and capped at 6, tap-to-add. Fully self-contained —
/// owns its own tag-list/suggestion state and talks to `editor`'s tag pass-throughs directly,
/// the same shape `NotesAppendComposer` already established for a detail-sheet subview that
/// drives its own save calls rather than routing them back through `ItemDetailView`.
///
/// `userId` is resolved from `StashClient.shared.auth.currentUser` rather than threaded in via
/// init: this view is only ever reachable once `SessionStore` has already resolved a signed-in
/// session (the same guarantee `SessionStore.start()` establishes before the tab bar — and
/// hence any detail sheet — can appear), so the synchronous, non-throwing `currentUser` accessor
/// is safe here. This keeps the change scoped to this file and `ItemDetailView.swift` rather
/// than also touching `LibraryView.swift` to plumb a new `userId` parameter through a view that
/// otherwise has no other reason to change in this task.
struct ItemTagsSection: View {
    let item: Item
    let editor: ItemEditor

    @State private var tags: [StashTag] = []
    @State private var availableTagNames: [String] = []
    @State private var inputValue = ""
    @State private var suggestions: [String] = []
    @State private var isSuggesting = false
    @State private var isAdding = false
    @State private var errorMessage: String?
    @State private var shimmerPhase: CGFloat = -1

    private var userId: UUID? { StashClient.shared.auth.currentUser?.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            tagChips
            inputRow
            suggestionsSection
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("detail.tags.error")
            }
        }
        .task { await loadAll() }
    }

    @ViewBuilder private var tagChips: some View {
        if !tags.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(tags) { tag in
                    chip(tag)
                }
            }
        }
    }

    private func chip(_ tag: StashTag) -> some View {
        Button {
            Task { await remove(tag) }
        } label: {
            HStack(spacing: 4) {
                Text(tag.name)
                Image(systemName: "xmark.circle.fill")
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("detail.tags.chip.\(tag.name)")
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("Add a tag…", text: $inputValue)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .onSubmit { Task { await addTyped() } }
                .accessibilityIdentifier("detail.tags.input")
            if isAdding {
                ProgressView()
            }
        }
    }

    @ViewBuilder private var suggestionsSection: some View {
        if isSuggesting {
            suggestionsShimmer
        } else if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Suggested")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 6) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) { Task { await add(suggestion) } }
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                            .accessibilityIdentifier("detail.tags.suggestion.\(suggestion)")
                    }
                }
            }
        }
    }

    /// Mirrors `ItemCardView`'s processing shimmer (same gradient/opacity/duration) rather than
    /// inventing a new loading treatment — "loading shimmer while suggesting" per the brief.
    private var suggestionsShimmer: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { _ in
                Capsule().fill(Color(.tertiarySystemFill)).frame(width: 60, height: 22)
            }
        }
        .overlay {
            GeometryReader { geo in
                LinearGradient(colors: [.clear, .white.opacity(0.6), .clear],
                                startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: shimmerPhase * geo.size.width)
            }
            .allowsHitTesting(false)
        }
        .clipShape(Rectangle())
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { shimmerPhase = 1.6 }
        }
        .accessibilityIdentifier("detail.tags.suggesting")
    }

    // MARK: - Actions

    private func addTyped() async {
        let name = inputValue
        inputValue = ""
        await add(name)
    }

    private func add(_ name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !tags.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        guard let userId else {
            errorMessage = "Couldn't add tag — try again."
            return
        }
        isAdding = true
        errorMessage = nil
        defer { isAdding = false }
        do {
            try await editor.addTag(named: trimmed, userId: userId, itemId: item.id)
            await reloadTags()
        } catch {
            errorMessage = "Couldn't add tag — try again."
        }
    }

    private func remove(_ tag: StashTag) async {
        errorMessage = nil
        do {
            try await editor.removeTag(tagId: tag.id, itemId: item.id)
            tags.removeAll { $0.id == tag.id }
            await refreshSuggestions()
        } catch {
            errorMessage = "Couldn't remove tag — try again."
        }
    }

    private func loadAll() async {
        if let current = try? await editor.itemTags(itemId: item.id) { tags = current }
        if let uid = userId, let all = try? await fetchTags(userId: uid) { availableTagNames = all.map(\.name) }
        await refreshSuggestions()
    }

    private func reloadTags() async {
        if let current = try? await editor.itemTags(itemId: item.id) { tags = current }
        await refreshSuggestions()
    }

    /// `suggestTags(title, plainText(content), description, availableTags)` — `plainText` mirrors
    /// `buildEmbeddingText`'s own TipTap-to-plain-text conversion (`EmbeddingRefresher.swift`)
    /// rather than sending the raw TipTap JSON to the AI suggestion endpoint.
    private func refreshSuggestions() async {
        guard !availableTagNames.isEmpty else { suggestions = []; return }
        isSuggesting = true
        defer { isSuggesting = false }
        let plainText = String(renderTipTap(item.content).characters)
        let applied = Set(tags.map { $0.name.lowercased() })
        guard let relevant = try? await editor.suggestTags(
            title: item.title ?? "", content: plainText, description: item.description ?? "",
            available: availableTagNames
        ) else {
            suggestions = []
            return
        }
        suggestions = Array(relevant.filter { !applied.contains($0.lowercased()) }.prefix(6))
    }
}

/// Minimal left-aligned wrapping row layout for tag chips — SwiftUI has no built-in flow
/// layout; `HStack` never wraps and `LazyVGrid` forces uniform per-row item counts, neither
/// fits a variable-width chip list. `Layout` (iOS 16+, this app targets 17) is the standard way
/// to implement one; kept private to this file since it has no other user yet.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var totalWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)
        return CGSize(width: maxWidth.isFinite ? maxWidth : totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.minX + bounds.width {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
