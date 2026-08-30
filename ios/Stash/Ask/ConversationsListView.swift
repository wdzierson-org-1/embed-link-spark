import SwiftUI
import StashKit

/// "Earlier conversations" (iOS port of the web's `ConversationsView`, reshaped for push
/// navigation): server-paged rows off `list_conversations` — search matches titles AND message
/// contents — bucketed Today / Yesterday / This week / month, with infinite scroll instead of
/// the web's Prev/Next buttons. Tapping a row loads that session into the thread (explicit,
/// gap-exempt) and pops back. This is the one pushed screen in the app; it wears the system
/// inline bar (back reads "‹ Ask") under the tab's hidden wordmark header, per the titling
/// convention in `StashDesign.swift`.
struct ConversationsListView: View {
    let store: ChatStore

    @Environment(\.dismiss) private var dismiss

    @State private var rows: [ConversationListRow] = []
    @State private var totalCount = 0
    @State private var searchInput = ""
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var openingId: UUID?
    @FocusState private var searchFocused: Bool

    private let pageSize = 25

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
            await loadFirstPage()
        }
    }

    private var searchPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(searchFocused ? StashColor.violet : StashColor.gray400)
            TextField("Search conversations", text: $searchInput)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .accessibilityIdentifier("convos.search")
            if !searchInput.isEmpty {
                Button { searchInput = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(StashColor.gray400)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(Color(.systemBackground), in: Capsule())
        .overlay(Capsule().strokeBorder(searchFocused ? StashColor.violet300 : StashColor.gray300,
                                        lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }

    @ViewBuilder private var list: some View {
        if isLoading && rows.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError {
            VStack(spacing: 8) {
                Text(loadError).font(.footnote).foregroundStyle(.secondary)
                Button("Try again") { Task { await loadFirstPage() } }
                    .font(.footnote.weight(.medium))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if rows.isEmpty {
            Text(searchInput.isEmpty ? "No conversations yet — ask something!" : "No matches.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("convos.empty")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        // Rows arrive newest-first, so a label change between neighbors is a
                        // bucket boundary — same one-pass grouping as web `bucketConversations`.
                        let label = ChatSessions.bucketLabel(for: row.lastMessageAt, now: Date())
                        if index == 0 || label != ChatSessions.bucketLabel(for: rows[index - 1].lastMessageAt, now: Date()) {
                            Text(label.uppercased())
                                .font(.system(size: 11, weight: .semibold))
                                .kerning(0.6)
                                .foregroundStyle(StashColor.gray400)
                                .padding(.top, index == 0 ? 2 : 10)
                        }
                        rowButton(row, index: index)
                            .onAppear {
                                if index == rows.count - 1, rows.count < totalCount {
                                    Task { await loadNextPage() }
                                }
                            }
                    }
                    if isLoading && !rows.isEmpty {
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
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title ?? "Untitled")
                    .font(.subheadline.weight(row.title == nil ? .regular : .semibold))
                    .italic(row.title == nil)
                    .foregroundStyle(row.title == nil ? .secondary : .primary)
                    .lineLimit(1)
                if let preview = row.preview, !preview.isEmpty {
                    Text(preview)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text("\(Self.rowDateFormatter.string(from: row.lastMessageAt)) · \(row.messageCount) message\(row.messageCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black.opacity(0.06), lineWidth: 1))
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
            .overlay {
                if openingId == row.id { ProgressView() }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("convos.row.\(index)")
    }

    // MARK: - Paging

    private func loadFirstPage() async {
        isLoading = true
        loadError = nil
        do {
            let page = try await store.listConversations(searchText: searchInput.isEmpty ? nil : searchInput,
                                                          pageLimit: pageSize, pageOffset: 0)
            rows = page
            totalCount = page.first?.totalCount ?? 0
        } catch {
            rows = []
            totalCount = 0
            loadError = "Couldn't load conversations."
        }
        isLoading = false
    }

    private func loadNextPage() async {
        guard !isLoading else { return }
        isLoading = true
        do {
            let page = try await store.listConversations(searchText: searchInput.isEmpty ? nil : searchInput,
                                                          pageLimit: pageSize, pageOffset: rows.count)
            // Guard against a mid-flight search change having already replaced `rows`.
            let known = Set(rows.map(\.id))
            rows.append(contentsOf: page.filter { !known.contains($0.id) })
            totalCount = page.first?.totalCount ?? totalCount
        } catch {
            // Non-fatal: the visible page stays; scrolling retriggers.
        }
        isLoading = false
    }

    private static let rowDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
