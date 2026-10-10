import CoreLocation
import ImageIO
import os
import StashKit
import Supabase
import SwiftUI
import UIKit

/// A compact share toast over the sending app. Save is explicit and durable-first; preview
/// enrichment, location resolution, and transport never hold the form or confirmation open.
struct ShareComposeView: View {
    let inputItems: [NSExtensionItem]
    let abandonTracker: ShareAbandonTracker
    let finish: () -> Void

    private enum Phase: Equatable {
        case loading, noSession, ready, saving, saved
        case failed(String)
    }

    @State private var phase: Phase = .loading
    @State private var objects: [SharedObject] = []
    @State private var droppedCount = 0
    @State private var note = ""
    @State private var expanded = false
    @State private var isPublic = false
    @State private var showsDictationHelp = false
    @State private var locationCapture: LocationCapture?
    /// A saved transfer may finish an already-requested pin after the toast disappears.
    @State private var locationOwnedByTransfer = false
    @State private var previewProvider = SharePreviewProvider()
    @State private var thumbnail: UIImage?
    @State private var userId: UUID?
    @State private var staging: StagedFileStore?
    @State private var canAddContent = true
    @State private var confirmationLatencyMs: Int?
    @State private var bodyHeight: CGFloat = 72
    @State private var headerHeight: CGFloat = 44
    @State private var actionsHeight: CGFloat = 44
    @FocusState private var noteFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let savedMessage = "Saved to Stash"
    static let failedMessage = "Couldn't save — try again"
    private static let log = Logger(subsystem: "it.gostash.stash", category: "share")

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                toastContent(availableHeight: max(0, geometry.size.height - 24))
                .frame(maxWidth: 480)
                .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .compositingGroup()
                .shadow(color: .black.opacity(0.16), radius: 24, x: 0, y: 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: geometry.size.height, alignment: .bottom)
        }
        .background(Color.clear)
        .task { await load() }
        // These start only after the share is materialized. Neither task is awaited by Save.
        .task(id: objects) {
            guard !objects.isEmpty else { return }
            await previewProvider.load(objects: objects, items: inputItems)
        }
        .task(id: objects) {
            let image = await Self.decodeThumbnail(for: objects)
            guard !Task.isCancelled else { return }
            thumbnail = image
        }
        .onChange(of: noteFocused) { _, focused in if focused { setExpanded(true) } }
        .onDisappear {
            previewProvider.cancel()
            if !locationOwnedByTransfer { locationCapture?.stop() }
        }
    }

    private func toastContent(availableHeight: CGFloat) -> some View {
        // Account for the card's 20pt top/bottom padding and 16pt sibling spacing.
        let showsActions = phase == .ready || phase == .saving
        let fixedHeight = 40 + headerHeight + (showsActions ? actionsHeight + 32 : 16)
        let viewportHeight = min(bodyHeight, max(1, availableHeight - fixedHeight))

        return VStack(alignment: .leading, spacing: 16) {
            header
                .simultaneousGesture(expandGesture)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
            // Keep dismissal and Save outside the scrolling region. In particular, expanded
            // accessibility text must not push either control behind the note keyboard.
            // A single scroll view also preserves the note field's identity when the keyboard
            // changes the viewport; replacing it with a fitting branch drops the first focus.
            ScrollView {
                toastBody
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bodyHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: viewportHeight)
            .accessibilityIdentifier("share.content")
            if showsActions {
                actions
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { actionsHeight = $0 }
            }
        }
        .padding(20)
    }

    private var toastBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch phase {
            case .loading:
                StashStatusLine(text: "reading share…")
                    .padding(.vertical, 12)
            case .noSession:
                Text("Open Stash and sign in, then share again.")
                    .stashFont(.reading).foregroundStyle(StashColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("share.noSession")
            case .ready, .saving, .saved, .failed:
                preview.simultaneousGesture(expandGesture)
                if droppedCount > 0 { droppedMessage }
                if case .failed(let message) = phase {
                    Text(message)
                        .stashFont(.secondary).foregroundStyle(StashColor.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("share.outcome")
                }
                Rectangle().fill(StashColor.lineSoft).frame(height: 1).accessibilityHidden(true)
                if phase == .saved {
                    if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(note).stashFont(.reading).foregroundStyle(StashColor.muted)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                    }
                } else {
                    noteField
                        .disabled(phase != .ready)
                    if expanded { expandedOptions.disabled(phase != .ready) }
                    if phase == .ready || phase == .saving {
                        if !canAddContent { gateMessage }
                    }
                }
            }
            #if DEBUG
            Text(fontStatus).font(.system(size: 1)).foregroundStyle(.clear).frame(height: 0)
                .accessibilityIdentifier("share.fontStatus").accessibilityLabel(fontStatus)
            #endif
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image("StashWordmark").resizable().scaledToFit().frame(width: 78, height: 20)
                .accessibilityLabel("Stash").accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if phase == .saved {
                Text("saved")
                    .stashFont(.machine).foregroundStyle(StashColor.ink)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(StashColor.spot)
                    .accessibilityLabel(Self.savedMessage)
                    .accessibilityIdentifier("share.outcome")
                    #if DEBUG
                    .accessibilityValue(confirmationLatencyMs.map { "\($0) ms" } ?? "")
                    #endif
            } else if phase == .saving {
                StashStatusLine(text: "saving…")
            } else {
                Button(action: cancel) {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .medium))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(StashColor.muted)
                .accessibilityLabel(isFailure ? "Close" : "Cancel")
                .accessibilityIdentifier("share.cancel")
            }
        }
        .frame(minHeight: 30)
    }

    private var preview: some View {
        HStack(alignment: .center, spacing: 14) {
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail).resizable().scaledToFill()
                } else {
                    StashColor.fill.overlay {
                        Image(systemName: previewSymbol)
                            .font(StashType.decorative(.book, size: 23))
                            .foregroundStyle(StashColor.ink)
                    }
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(previewTitle)
                    .stashFont(.secondaryMedium).foregroundStyle(StashColor.ink)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(previewIdentifier)
                    .accessibilityLabel(previewAccessibilityLabel)
                Text(previewSummary)
                    .stashFont(.machine).foregroundStyle(StashColor.muted)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                if objects.count > 1 {
                    Text("\(objects.count) items · note on the first item")
                        .stashFont(.machine).foregroundStyle(StashColor.muted)
                        .accessibilityIdentifier("share.preview.overflow")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var previewTitle: String {
        if objects.count > 1 { return "\(objects.count) items\(phase == .saved ? " saved" : " to stash")" }
        if let title = previewProvider.title, !title.isEmpty { return title }
        guard let first = objects.first else { return "Nothing to share" }
        switch first {
        case .url(let value): return domain(from: value) ?? value
        case .text(let text): return String(text.prefix(160)) + (text.count > 160 ? "…" : "")
        case .file(_, let mime, let name, _): return name ?? (mime.hasPrefix("image/") ? "Image" : "File")
        }
    }

    private var previewSummary: String {
        if let summary = previewProvider.summary, !summary.isEmpty { return summary }
        guard let first = objects.first else { return "This share has no supported content." }
        switch first {
        case .url(let url): return url
        case .text: return "a note for your stash"
        case .file(_, let mime, _, _):
            let status = phase == .saved ? "saved to your stash" : "ready to save"
            if mime.hasPrefix("image/") { return "image · \(status)" }
            if mime.hasPrefix("video/") { return "video · \(status)" }
            if mime.hasPrefix("audio/") { return "audio · \(status)" }
            if mime == "application/pdf" { return "PDF · \(status)" }
            return "file · \(status)"
        }
    }

    private var previewIdentifier: String {
        guard let first = objects.first else { return "share.preview.empty" }
        switch first {
        case .url: return "share.preview.url"
        case .text: return "share.preview.text"
        case .file: return "share.preview.files"
        }
    }

    private var previewAccessibilityLabel: String {
        if case .url(let url) = objects.first { return "\(previewTitle), \(url)" }
        return previewTitle
    }

    private var previewSymbol: String {
        guard let first = objects.first else { return "tray" }
        switch first {
        case .url: return "link"
        case .text: return "text.alignleft"
        case .file(_, let mime, _, _):
            if mime.hasPrefix("image/") { return "photo" }
            if mime.hasPrefix("video/") { return "video" }
            if mime.hasPrefix("audio/") { return "waveform" }
            return "doc"
        }
    }

    private var noteField: some View {
        TextField("Add a note", text: $note,
                  prompt: Text("Add a note").foregroundStyle(StashColor.muted), axis: .vertical)
            .focused($noteFocused).textFieldStyle(.plain).stashFont(.reading)
            .lineLimit(1...(expanded ? 5 : 2))
            .padding(.vertical, 10)
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { noteFocused = true })
            .accessibilityIdentifier("share.note")
    }

    private var expandedOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let locationCapture {
                Button { locationCapture.toggle() } label: {
                    HStack(spacing: 10) {
                        StashMapPin().stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                            .frame(width: 18, height: 18)
                        Text("Include location").stashFont(.secondary)
                        Spacer(minLength: 8)
                        if locationCapture.state == .resolving { StashCursor() }
                        Text(locationCapture.enabled ? "on" : "off").stashFont(.machine)
                    }
                    .foregroundStyle(StashColor.ink).frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Include your location")
                .accessibilityValue(locationCapture.enabled ? "On" : "Off")
                .accessibilityIdentifier("share.pin")
                if case .ready(let location) = locationCapture.state {
                    Text("posted from \(location.label)")
                        .stashFont(.machine).foregroundStyle(StashColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("share.pin.preview")
                } else if locationCapture.requiresAppPermission {
                    Text("Enable location permission in Stash to include your location here.")
                        .stashFont(.secondary).foregroundStyle(StashColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } else if locationCapture.state == .failed {
                    Text("Location is unavailable. Your item can still be saved.")
                        .stashFont(.secondary).foregroundStyle(StashColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Toggle(isOn: $isPublic) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Share this stash").stashFont(.secondary)
                    Text("Make \(objects.count > 1 ? "these items" : "this item") public.")
                        .stashFont(.machine).foregroundStyle(StashColor.muted)
                }
            }
            .toggleStyle(StashSwitchStyle())
            .accessibilityIdentifier("share.public")
            Button {
                showsDictationHelp = true
                noteFocused = true
            } label: {
                Label("Dictate a note", systemImage: "mic")
                    .stashFont(.secondaryMedium).frame(minHeight: 44)
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(StashColor.ink)
            .accessibilityHint("Shows how to use keyboard dictation in the note field")
            .accessibilityIdentifier("share.dictate")
            if showsDictationHelp {
                Text("Tap the microphone on your keyboard to dictate. If dictation isn’t available, type your note.")
                    .stashFont(.secondary).foregroundStyle(StashColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("share.dictate.help")
            }
        }
        .padding(.top, 4)
    }

    private var actions: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) { moreOptions; saveButton }
            } else {
                HStack(spacing: 12) { moreOptions; saveButton }
            }
        }
    }

    private var moreOptions: some View {
        Button { setExpanded(!expanded) } label: {
            Label(expanded ? "Less" : "More options", systemImage: expanded ? "chevron.down" : "chevron.up")
                .stashFont(.secondary).frame(minHeight: 44)
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(StashColor.muted)
        .disabled(phase != .ready)
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
        .accessibilityIdentifier("share.moreOptions")
    }

    private var saveButton: some View {
        Button { Task { await save() } } label: {
            Text(phase == .saving ? "Saving…" : "Save")
                .stashFont(.textButtonProminent)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(canSubmit || phase == .saving ? .white : StashColor.muted)
                .background(canSubmit || phase == .saving ? StashColor.ink : StashColor.fill,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain).disabled(!canSubmit)
        .accessibilityIdentifier("share.save")
    }

    private var canSubmit: Bool { phase == .ready && canAddContent && !objects.isEmpty }
    private var isFailure: Bool { if case .failed = phase { return true }; return false }

    private var gateMessage: some View {
        Text("An active subscription is required to save new items.")
            .stashFont(.secondary).foregroundStyle(StashColor.muted)
            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("share.gate")
    }

    private var droppedMessage: some View {
        Text(droppedCount == 1 ? "1 item couldn’t be read." : "\(droppedCount) items couldn’t be read.")
            .stashFont(.secondary).foregroundStyle(StashColor.muted)
            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("share.dropped")
    }

    private var expandGesture: some Gesture {
        DragGesture(minimumDistance: 24).onEnded { value in
            guard phase == .ready, value.translation.height < -32,
                  abs(value.translation.height) > abs(value.translation.width) else { return }
            setExpanded(true)
        }
    }

    private func setExpanded(_ value: Bool) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { expanded = value }
    }

    private func load() async {
        guard let resolvedUserId = StashClient.shared.auth.currentSession?.user.id else {
            phase = .noSession
            return
        }
        userId = resolvedUserId
        let location = LocationCapture(userId: resolvedUserId, allowsAuthorizationRequest: false)
        locationCapture = location
        location.resume()
        let store = StagedFileStore(userId: resolvedUserId)
        staging = store
        let result = await ProviderLoader(staging: store).load(from: inputItems)
        // Track immediately, including after a mid-load dismissal, so abandoned staged files
        // cannot later reappear through orphan recovery.
        abandonTracker.track(objects: result.objects, staging: store)
        guard !Task.isCancelled else { return }
        objects = result.objects
        droppedCount = result.droppedCount
        canAddContent = readGateCache()
        phase = .ready
    }

    private func readGateCache() -> Bool {
        guard let defaults = UserDefaults(suiteName: AppGroup.identifier) else { return true }
        #if DEBUG
        if defaults.bool(forKey: "uitest.shareGateOpen") { return true }
        #endif
        guard defaults.object(forKey: SubscriptionStore.gateCacheKey) != nil else { return true }
        return defaults.bool(forKey: SubscriptionStore.gateCacheKey)
    }

    private func save() async {
        guard canSubmit, let userId, let staging else { return }
        abandonTracker.markConsumed() // Intent boundary: before the first suspension.
        phase = .saving
        noteFocused = false
        let tapped = ContinuousClock.now
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let intake = ShareIntake(userId: userId, staging: staging,
                                accessToken: { try await StashClient.accessToken(for: userId) })
        let pendingLocation = locationCapture?.state == .resolving ? locationCapture : nil
        locationOwnedByTransfer = pendingLocation != nil
        let location = locationCapture?.currentLocation
        // Pending is immediately recoverable by the app even if the extension dies before the
        // transport task starts. It is promoted to transferring by BackgroundCaptureTransfers.
        let entries = await Self.keepingProcessAwake("Saving the share to Stash") {
            await intake.enqueueForTransfer(objects, note: trimmedNote.isEmpty ? nil : trimmedNote,
                                            location: location, status: .pending, isPublic: isPublic)
        }
        let persisted = ContinuousClock.now
        confirmationLatencyMs = Self.ms(since: tapped)
        if !entries.isEmpty {
            // Keep transport alive independently of the UI's half-second confirmation. It owns
            // only the durable entries/intake, not this SwiftUI tree or its preview images.
            let token = Self.currentTransferToken(for: userId)
            Task {
                await Self.keepingProcessAwake("Handing the share to Stash") {
                    await Self.transfer(entries, intake: intake, userId: userId, token: token,
                                        pendingLocation: pendingLocation)
                }
            }
        } else {
            pendingLocation?.stop()
            locationOwnedByTransfer = false
        }
        guard entries.count == objects.count else {
            // Never show a green saved badge for a partial write. Dispose only unqueued file
            // copies, so orphan recovery cannot save content that this UI reported as failed.
            let persistedPaths = Set(entries.compactMap { $0.payload["local_file_path"] })
            for object in objects {
                if case .file(let url, _, _, _) = object, !persistedPaths.contains(url.path) { staging.discard(url) }
            }
            let message = entries.isEmpty
                ? "Couldn’t save this share. Close and try sharing again."
                : "Saved \(entries.count) of \(objects.count) items. The remaining items couldn’t be saved; please share them again."
            phase = .failed(message)
            UIAccessibility.post(notification: .announcement, argument: message)
            Self.log.error("save: persisted \(entries.count) of \(objects.count) objects")
            return
        }
        phase = .saved
        UIAccessibility.post(notification: .announcement, argument: Self.savedMessage)
        Self.log.notice("save: \(entries.count) objects durable after \(Self.ms(since: tapped)) ms")
        try? await Task.sleep(until: persisted + Self.confirmationWindow, clock: .continuous)
        finish()
    }

    @MainActor
    private static func transfer(_ savedEntries: [OutboxEntry], intake: ShareIntake, userId: UUID,
                                 token initialToken: String?, pendingLocation: LocationCapture?) async {
        var entries = savedEntries
        if let pendingLocation {
            // Resolution and attachment continue under the process assertion, independent of
            // the toast's lifetime. Read consent again at attachment; an opt-out must win.
            _ = await pendingLocation.awaitResolution(timeout: 2.5)
            let location = pendingLocation.currentLocation
            // Release the location manager before the actor/file-lock work below.
            pendingLocation.stop()
            if let location {
                entries = await intake.attachLocation(location, to: entries)
            }
        }
        guard !entries.isEmpty else { return }
        var token = initialToken
        if token == nil {
            token = await ShareIntake.refreshedTransferToken {
                let session = try await StashClient.shared.auth.refreshSession()
                guard session.user.id == userId else { throw CaptureError.badStatus(401) }
                return session.accessToken
            }
        }
        guard let token else { return } // Durable pending entries remain for the app.
        let transfers = BackgroundCaptureTransfers.shared
        let batch = await transfers.start(entries: entries, userId: userId, accessToken: token)
        #if DEBUG
        if let exitAfter = uiTestExitAfterHandoff {
            try? await Task.sleep(for: exitAfter)
            exit(0)
        }
        #endif
        try? await Task.sleep(for: .milliseconds(500))
        let fallback = await transfers.entriesNeedingForegroundSend(in: batch)
        if !fallback.isEmpty { _ = await intake.sendInForeground(fallback, accessToken: token) }
    }

    private static func keepingProcessAwake<Result>(_ reason: String, limit: TimeInterval = 15,
                                                    _ work: () async -> Result) async -> Result {
        let finished = DispatchSemaphore(value: 0)
        ProcessInfo.processInfo.performExpiringActivity(withReason: reason) { expired in
            guard !expired else { return }
            _ = finished.wait(timeout: .now() + limit)
        }
        let result = await work()
        finished.signal()
        return result
    }

    private static func currentTransferToken(for userId: UUID) -> String? {
        guard let session = StashClient.shared.auth.currentSession, session.user.id == userId else { return nil }
        return ShareIntake.usableTransferToken(session.accessToken,
                                               expiresAt: Date(timeIntervalSince1970: session.expiresAt))
    }

    private static var confirmationWindow: Duration {
        #if DEBUG
        let hold = UserDefaults(suiteName: AppGroup.identifier)?.integer(forKey: "uitest.shareConfirmationHoldMs") ?? 0
        if hold > 0 { return .milliseconds(hold) }
        #endif
        return .milliseconds(500)
    }

    private static func ms(since start: ContinuousClock.Instant) -> Int {
        let elapsed = ContinuousClock.now - start
        return Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }

    #if DEBUG
    private var fontStatus: String {
        "font:\(StashType.isNeueMontrealAvailable ? "neue-montreal" : "sf-fallback") departure:\(StashType.isDepartureMonoAvailable ? "loaded" : "fallback") jetbrains:\(StashType.isJetBrainsMonoAvailable ? "loaded" : "fallback")"
    }
    private static var uiTestExitAfterHandoff: Duration? {
        let ms = UserDefaults(suiteName: AppGroup.identifier)?.integer(forKey: "uitest.shareExitAfterHandoffMs") ?? 0
        return ms > 0 ? .milliseconds(ms) : nil
    }
    #endif

    private func domain(from value: String) -> String? {
        URLComponents(string: value)?.host ?? URLComponents(string: "https://\(value)")?.host
    }

    private static func decodeThumbnail(for objects: [SharedObject]) async -> UIImage? {
        guard case .file(let url, let mime, _, _) = objects.first, mime.hasPrefix("image/") else { return nil }
        return await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL,
                [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 180, kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return UIImage(cgImage: image)
        }.value
    }

    private func cancel() {
        abandonTracker.discardIfAbandoned()
        finish()
    }
}
