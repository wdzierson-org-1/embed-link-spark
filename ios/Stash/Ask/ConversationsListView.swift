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
struct ConversationsListView: View {
    let store: ChatStore

    @Environment(\.dismiss) private var dismiss

    @State private var pager: ConversationsPager
    @State private var searchInput = ""
    @State private var openingId: UUID?
    @FocusState private var searchFocused: Bool

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
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(searchFocused ? StashColor.violet600 : StashColor.faint)
            TextField("Search conversations", text: $searchInput)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .accessibilityIdentifier("convos.search")
            if !searchInput.isEmpty {
                Button { searchInput = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(StashColor.faint)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(Color(.systemBackground), in: Capsule())
        .overlay(Capsule().strokeBorder(searchFocused ? StashColor.violet300 : StashColor.hairline,
                                        lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }

    @ViewBuilder private var list: some View {
        let rows = pager.rows
        if pager.isLoading && rows.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError = pager.loadError {
            VStack(spacing: 8) {
                Text(loadError).font(StashType.meta()).foregroundStyle(StashColor.muted)
                Button("Try again") { Task { await pager.loadFirstPage(query: searchInput) } }
                    .font(StashType.bodyMedium(12))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if rows.isEmpty {
            Text(searchInput.isEmpty ? "No conversations yet — ask something!" : "No matches.")
                .font(StashType.meta())
                .foregroundStyle(StashColor.muted)
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
                            Text(label.uppercased())
                                .font(StashType.microLabel())
                                .stashTracking(0.11, size: 11)
                                .foregroundStyle(StashColor.faint)
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
            Task {
                await store.openConversation(id: row.id, title: row.title)
                openingId = nil
                dismiss()
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                // Web's `ConversationsView.tsx` violet-300 dot (`h-2 w-2 rounded-full
                // bg-violet-300`) — purely decorative, so it's excluded from the row's a11y tree.
                Circle()
                    .fill(StashColor.violet300)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.title ?? "Untitled")
                        .font(StashType.bodyMedium())
                        .italic(row.title == nil)
                        .foregroundStyle(row.title == nil ? StashColor.muted : StashColor.ink)
                        .lineLimit(1)
                    if let preview = row.preview, !preview.isEmpty {
                        Text(preview)
                            .font(StashType.meta())
                            .foregroundStyle(StashColor.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Self.rowDateFormatter.string(from: row.lastMessageAt))
                    Text("\(row.messageCount) message\(row.messageCount == 1 ? "" : "s")")
                }
                .font(StashType.meta())
                .foregroundStyle(StashColor.faint)
            }
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
