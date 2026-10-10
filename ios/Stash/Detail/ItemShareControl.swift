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
    @State private var retryRevocation = false
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
        .accessibilityLabel(link.url == nil ? "Share item" : "Manage item share link")
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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Anyone with the link can read this item and its notes.")
                        .stashFont(.reading).foregroundStyle(StashColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let errorMessage {
                        Text(errorMessage).stashFont(.secondary).foregroundStyle(StashColor.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("detail.share.error")
                        Button("Try again") {
                            Task {
                                if retryRevocation { await revokeLink() }
                                else { await createOrOpenLink() }
                            }
                        }
                            .buttonStyle(.stashPlain).disabled(isBusy)
                            .accessibilityIdentifier("detail.share.retry")
                    }
                    if isBusy { StashStatusLine(text: "updating link…") }
                    if let url = link.url {
                        Text(url.absoluteString)
                            .stashFont(.mono(.footnote)).foregroundStyle(StashColor.ink)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(Rectangle().strokeBorder(StashColor.line, lineWidth: 1))
                            .accessibilityIdentifier("detail.share.url")
                        Button {
                            UIPasteboard.general.url = url
                            copied = true
                            UIAccessibility.post(notification: .announcement, argument: "Link copied")
                        } label: {
                            Label(copied ? "Link copied" : "Copy link", systemImage: copied ? "checkmark" : "doc.on.doc")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.stashPlain).disabled(isBusy)
                        .accessibilityIdentifier("detail.share.copy")
                        ShareLink(item: url) {
                            Label("Share link…", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.stashPlain).disabled(isBusy)
                        .accessibilityIdentifier("detail.share.system")
                        Text(isPublic ? "This item is also on your public feed." : "This link does not add the item to your public feed.")
                            .stashFont(.secondary).foregroundStyle(StashColor.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Stop sharing this link", role: .destructive) { Task { await revokeLink() } }
                            .buttonStyle(.stashPlain).disabled(isBusy)
                            .foregroundStyle(StashColor.destructive)
                            .accessibilityIdentifier("detail.share.revoke")
                    }
                }
                .stashFont(.secondaryMedium)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(StashColor.surface)
            .navigationTitle("Share item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showsPanel = false }
                        .accessibilityIdentifier("detail.share.done")
                }
            }
        }
        .tint(StashColor.ink)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @MainActor private func createOrOpenLink() async {
        guard !isBusy else { return }
        generation += 1
        isBusy = true
        errorMessage = nil
        retryRevocation = false
        defer { isBusy = false }
        do { link = try await service.share(itemID: itemID, userID: userID) }
        catch { errorMessage = message(for: error) }
    }

    @MainActor private func revokeLink() async {
        guard !isBusy, let token = link.token else { return }
        generation += 1
        isBusy = true
        errorMessage = nil
        retryRevocation = true
        defer { isBusy = false }
        do {
            link = try await service.revoke(itemID: itemID, userID: userID, token: token)
            copied = false
            showsPanel = false
            UIAccessibility.post(notification: .announcement, argument: "Share link stopped")
        } catch {
            if error as? ItemShareError == .changedElsewhere { retryRevocation = false }
            errorMessage = message(for: error)
        }
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
