import SwiftUI
import StashKit

/// "Earlier conversations" (iOS port of the web's `ConversationsView`, reshaped for push
/// navigation): server-paged rows off `list_conversations` — search matches titles AND message
/// contents — bucketed Today / Yesterday / This week / month, with infinite scroll instead of
/// the web's Prev/Next buttons. Tapping a row loads that session into the thread (explicit,
/// gap-exempt) and pops back. This is the one pushed screen in the app; it wears the system
/// inline bar (back reads "‹ Ask") under the tab's hidden wordmark header, per the titling
/// convention in `StashDesign.swift`.
///
/// Paging state lives in StashKit's `ConversationsPager` (plan 15, M6): a cancelled load (the
/// debounced search restarting as you type) is no longer shown as "Couldn't load conversations."
/// with the list wiped, and a page for a superseded query is dropped instead of replacing or
/// being appended to the current results.
///
/// Plan 16 (task 2d, accessibility): text takes the type roles and scales with Dynamic Type — row
/// titles 15 Medium, previews 15, dates and counts 13 in `muted` (they were `faint`, 2.79:1), bucket
/// headers the section micro-label (and VoiceOver headings); the search field reads at 17 with a
/// `muted` placeholder, in a pill at least 44 pt tall that grows with it and focuses the field
/// wherever it's tapped, and its clear button takes taps across 44 pt;
/// "Try again" is an inline action at 15 pt; and at accessibility sizes a row stacks its date and count
/// under its title, which wraps instead of being cut.
struct ConversationsListView: View {
    let store: ChatStore

    @Environment(\.dismiss) private var dismiss

    @State private var pager: ConversationsPager
    @State private var searchInput = ""
    @State private var openingId: UUID?
    @FocusState private var searchFocused: Bool
    /// The search field's own frame in the pill (`searchPillSpace`): the hole in the pill's tap ring.
    @State private var searchFieldFrame: CGRect = .zero
    private static let searchPillSpace = "convos.searchPill"

    init(store: ChatStore) {
        self.store = store
        _pager = State(initialValue: ConversationsPager { searchText, limit, offset in
            try await store.listConversations(searchText: searchText, pageLimit: limit, pageOffset: offset)
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            searchPill
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 10)
            list
        }
        .background(Color(.systemBackground))
        .navigationTitle("Conversations")
        .navigationBarTitleDisplayMode(.inline)
        // Debounced server search (web: 300ms) — also performs the initial load (empty query).
        .task(id: searchInput) {
            if !searchInput.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            await pager.loadFirstPage(query: searchInput)
        }
    }

    private var searchPill: some View {
        HStack(spacing: 8) {
            // The field's own glyph, at the supporting size it always had (15 pt), now scaling.
            Image(systemName: "magnifyingglass")
                .stashFont(.secondary)
                .foregroundStyle(searchFocused ? StashColor.violet600 : StashColor.muted)
                .contentShape(Rectangle())
                .onTapGesture { searchFocused = true }
                .accessibilityHidden(true)
            TextField("Search conversations", text: $searchInput,
                      prompt: Text("Search conversations").foregroundStyle(StashColor.muted))
                .stashFont(.reading)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .accessibilityIdentifier("convos.search")
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.searchPillSpace)) } action: {
                    searchFieldFrame = $0
                }
            if !searchInput.isEmpty {
                Button { searchInput = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .stashFont(.secondary)
                        .foregroundStyle(StashColor.muted)
                }
                .buttonStyle(.stashPlain)
                .stashIconControl("Clear search", systemImage: "xmark.circle.fill")
                .accessibilityIdentifier("convos.search.clear")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .coordinateSpace(.named(Self.searchPillSpace))
        .background {
            // The whole pill focuses the field — the magnifier (above) and everything around the field
            // too (the field's own frame is just its text line) — as the View tab's search pill does
            // (plan 16). Not over the field itself: there the gesture would take the field's own taps, as
            // it did the composer's on iOS 18.5 (`AskPillPadding`). So the ring's hole is the field's own
            // frame, measured (task 2d fix round 1, M-1): a hole of the 44 pt pill less its 4 pt padding
            // left a band 5–7 pt above and below the field's line that focused nothing (iOS 26.5). In
            // front of the fill, or the fill takes the tap.
            Color.clear
                .contentShape(AskPillRing(hole: searchFieldFrame), eoFill: true)
                .onTapGesture { searchFocused = true }
                .accessibilityHidden(true)
        }
        .background {
            Capsule()
                .fill(Color(.systemBackground))
                .accessibilityHidden(true)
        }
        .overlay {
            Capsule()
                .strokeBorder(searchFocused ? StashColor.violet300 : StashColor.hairline, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }

    @ViewBuilder private var list: some View {
        let rows = pager.rows
        if pager.isLoading && rows.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError = pager.loadError {
            VStack(spacing: 8) {
                Text(loadError)
                    .stashFont(.meta)
                    .foregroundStyle(StashColor.muted)
                    .multilineTextAlignment(.center)
                Button("Try again") { Task { await pager.loadFirstPage(query: searchInput) } }
                    .stashFont(.inlineButton)
                    .foregroundStyle(StashColor.violet600)
                    .buttonStyle(.stashPlain)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if rows.isEmpty {
            Text(searchInput.isEmpty ? "No conversations yet — ask something!" : "No matches.")
                .stashFont(.secondary)
                .foregroundStyle(StashColor.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("convos.empty")
        } else {
            let now = Date()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        // Rows arrive newest-first, so a label change between neighbors is a
                        // bucket boundary — same one-pass grouping as web `bucketConversations`.
                        let label = ChatSessions.bucketLabel(for: row.lastMessageAt, now: now)
                        if index == 0 || label != ChatSessions.bucketLabel(for: rows[index - 1].lastMessageAt, now: now) {
                            Text(label)
                                .stashMicroLabel()
                                .accessibilityAddTraits(.isHeader)
                                .padding(.top, index == 0 ? 2 : 10)
                        }
                        rowButton(row, index: index)
                            .onAppear {
                                if index == rows.count - 1, pager.hasMore {
                                    Task { await pager.loadNextPage() }
                                }
                            }
                    }
                    if pager.isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.immediately)
            .accessibilityIdentifier("convos.list")
        }
    }

    private func rowButton(_ row: ConversationListRow, index: Int) -> some View {
        Button {
            guard openingId == nil else { return }
            openingId = row.id
            // Plan 16: the search keyboard goes down with the tap, not at the end of the load
            // and pop — the conversation lands on the Ask thread with no keyboard up.
            searchFocused = false
            Task {
                await store.openConversation(id: row.id, title: row.title)
                openingId = nil
                dismiss()
            }
        } label: {
            ConversationRowLabel(row: row, date: Self.rowDateFormatter.string(from: row.lastMessageAt))
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: StashRadius.card))
                .overlay(RoundedRectangle(cornerRadius: StashRadius.card).strokeBorder(StashColor.hairline, lineWidth: 1))
                .stashCardShadow()
                .overlay {
                    if openingId == row.id { ProgressView() }
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("convos.row.\(index)")
    }

    private static let rowDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

/// One conversation's row: the web's violet dot, its title and preview, and its date and message count
/// — on the right up to the largest standard text size, under the preview at accessibility sizes, where
/// the title and preview wrap to a few lines rather than being cut at one (plan 16, task 2d). Above the
/// default size the title may take two lines beside the date.
private struct ConversationRowLabel: View {
    let row: ConversationListRow
    let date: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The title's first line (18 pt at the default size), grown with it: the dot is centred on it.
    @ScaledMetric(relativeTo: .subheadline) private var titleLine: CGFloat = 18
    private var dotTop: CGFloat { (titleLine - 8) / 2 }

    var body: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        HStack(alignment: .top, spacing: 10) {
            // Web's `ConversationsView.tsx` violet-300 dot (`h-2 w-2 rounded-full bg-violet-300`) —
            // purely decorative, so it's excluded from the row's a11y tree.
            Circle()
                .fill(StashColor.violet300)
                .frame(width: 8, height: 8)
                .padding(.top, dotTop)
                .accessibilityHidden(true)
            if stacked {
                VStack(alignment: .leading, spacing: 3) {
                    title(lines: 3)
                    preview(lines: 3)
                    Text("\(date) · \(count)")
                        .stashFont(.meta)
                        .foregroundStyle(StashColor.muted)
                }
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    // One line at the default size, as before; two above it, where the date beside it
                    // leaves a title only half its width ("Scripted long conv…" at xxxLarge).
                    title(lines: dynamicTypeSize > .large ? 2 : 1)
                    preview(lines: 1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(date)
                    Text(count)
                }
                .stashFont(.meta)
                .foregroundStyle(StashColor.muted)
            }
        }
    }

    private var count: String { "\(row.messageCount) message\(row.messageCount == 1 ? "" : "s")" }

    /// An untitled conversation reads "Untitled" in the italic face, `muted`.
    private func title(lines: Int) -> some View {
        Text(row.title ?? "Untitled")
            .stashFont(row.title == nil ? .secondaryItalic : .secondaryMedium)
            .foregroundStyle(row.title == nil ? StashColor.muted : StashColor.ink)
            .lineLimit(lines)
    }

    @ViewBuilder private func preview(lines: Int) -> some View {
        if let preview = row.preview, !preview.isEmpty {
            Text(preview)
                .stashFont(.secondary)
                .foregroundStyle(StashColor.muted)
                .lineLimit(lines)
        }
    }
}

/// The search pill less the field itself (plan 16, task 2d fix round 1, M-1): the hole is the field's own
/// frame, measured in the pill, so a tap anywhere else on the pill can focus the field while a tap on the
/// field always reaches the field. No ring until the field has been measured: a pill with no hole would take
/// the field's own taps.
private struct AskPillRing: Shape {
    let hole: CGRect

    func path(in rect: CGRect) -> Path {
        guard !hole.isEmpty else { return Path() }
        var path = Path(rect)
        path.addRect(hole)
        return path
    }
}
