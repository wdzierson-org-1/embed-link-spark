import StashKit
import SwiftUI
import UIKit

/// An unlisted item link. This never changes whether the item appears on the public feed.
struct ItemShareControl: View {
    let itemID: UUID
    let userID: UUID
    let isPublic: Bool

    @State private var link = ItemShareState()
    @State private var showsPanel = false
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var copied = false
    @State private var generation = 0
    @State private var contentHeight: CGFloat = 120
    @State private var headerHeight: CGFloat = 44
    @State private var actionHeight: CGFloat = 52
    private let service = ItemShareService()

    var body: some View {
        Button {
            showsPanel = true
            copied = false
            Task { await createOrOpenLink() }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 18))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(link.url == nil ? StashColor.white : StashColor.spotOnInk)
        .disabled(isBusy)
        .accessibilityLabel("Share item")
        .accessibilityHint("Anyone with the link can read this item and its notes")
        .accessibilityIdentifier("detail.share")
        .task(id: itemID) {
            guard !isBusy else { return }
            let current = generation
            if let existing = try? await service.current(itemID: itemID, userID: userID),
               current == generation, !isBusy, !Task.isCancelled { link = existing }
        }
        .sheet(isPresented: $showsPanel) { panel }
    }

    private var panel: some View {
        GeometryReader { geometry in
            toast(availableHeight: max(1, geometry.size.height))
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity, maxHeight: geometry.size.height, alignment: .bottom)
        }
        .tint(StashColor.ink)
        .presentationBackground(StashColor.paper)
        .presentationCornerRadius(24)
        .presentationDetents([.height(idealPanelHeight)])
        .presentationDragIndicator(.hidden)
    }

    // The sheet fits ordinary text and grows for Dynamic Type. At the system's maximum
    // height, only the body scrolls: Close and Copy remain available in either orientation.
    private var idealPanelHeight: CGFloat { contentHeight + headerHeight + actionHeight + 72 }

    private func toast(availableHeight: CGFloat) -> some View {
        let fixedHeight = headerHeight + actionHeight + 72 // 40pt padding + two 16pt gaps.
        let viewportHeight = min(contentHeight, max(1, availableHeight - fixedHeight))
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text("Share item")
                    .stashFont(.cardTitle)
                    .foregroundStyle(StashColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button { showsPanel = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 44, height: 44)
                        .background(StashColor.white, in: Rectangle())
                        .clipShape(Rectangle())
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(StashColor.ink)
                .accessibilityLabel("Close")
                .accessibilityIdentifier("detail.share.close")
            }
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Anyone with the link can read this item and its notes.")
                        .stashFont(.reading)
                        .foregroundStyle(StashColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let errorMessage {
                        Text(errorMessage)
                            .stashFont(.secondary)
                            .foregroundStyle(StashColor.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("detail.share.error")
                    }
                    if isBusy { StashStatusLine(text: "preparing link…") }
                    if let url = link.url {
                        Text(url.absoluteString)
                            .stashFont(.code(.footnote))
                            .foregroundStyle(StashColor.ink)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(StashColor.white)
                            .overlay(Rectangle().strokeBorder(StashColor.line, lineWidth: 1))
                            .accessibilityIdentifier("detail.share.url")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: viewportHeight)
            .accessibilityIdentifier("detail.share.content")
            copyButton
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { actionHeight = $0 }
        }
        .padding(20)
    }

    private var canRetry: Bool { errorMessage != nil && link.url == nil }

    private var copyButton: some View {
        Button {
            if canRetry {
                Task { await createOrOpenLink() }
            } else if let url = link.url {
                UIPasteboard.general.url = url
                copied = true
                UIAccessibility.post(notification: .announcement, argument: "Link copied")
            }
        } label: {
            Text(canRetry ? "Try again" : (copied ? "Link copied" : "Copy link"))
                .stashFont(.textButtonProminent)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(StashColor.white)
                .background(StashColor.ink, in: Rectangle())
                .clipShape(Rectangle())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy || (link.url == nil && !canRetry))
        .accessibilityIdentifier(canRetry ? "detail.share.retry" : "detail.share.copy")
    }

    @MainActor private func createOrOpenLink() async {
        guard !isBusy else { return }
        generation += 1
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do { link = try await service.share(itemID: itemID, userID: userID) }
        catch { errorMessage = message(for: error) }
    }

    private func message(for error: Error) -> String {
        switch error as? ItemShareError {
        case .signedOut: return "Sign in to Stash again to manage this link."
        case .notFound: return "This item is no longer available."
        case .changedElsewhere: return "The link changed on another device. Try again to load the current link."
        default: return "Couldn’t update the link. Check your connection and try again."
        }
    }
}
