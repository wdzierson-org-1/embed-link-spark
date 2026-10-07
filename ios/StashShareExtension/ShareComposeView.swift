import CoreGraphics
import CoreLocation
import ImageIO
import os
import StashKit
import Supabase
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The real share-extension compose card (Task 7) — replaces Task 5's placeholder. Compact,
/// type-appropriate preview, an optional note, an optional location pin (reusing the app's own
/// `LocationCapture` state machine — see `project.yml`'s doc comment on why that file is shared
/// into this target rather than re-implemented), and a Save button.
///
/// Plan 15 Task 4: Save no longer waits on the network. It writes the share to the Outbox, hands
/// it to the shared background `URLSession` (`BackgroundCaptureTransfers`), shows "Saved to Stash"
/// at once, and dismisses ~0.8 s later; the upload finishes in the background (the system wakes
/// the app for it if the extension is gone). The user always sees a confirmation, never an
/// error, never a spinner longer than that window.
struct ShareComposeView: View {
    /// What was shared (`NSExtensionContext.inputItems`). Plan 15 review: the card never holds the
    /// context itself — see `ShareViewController`'s doc comment.
    let inputItems: [NSExtensionItem]
    /// Owned by `ShareViewController` (persists across this struct's own re-creations) — see
    /// `ShareAbandonTracker`'s own doc comment for the abandon/discard contract this implements.
    let abandonTracker: ShareAbandonTracker
    /// Ends the share (`completeRequest`), through a weak reference to the host controller.
    let finish: () -> Void

    private enum Phase: Equatable {
        case loading
        case noSession
        case ready
        case saving
        case done(String)
    }

    @State private var phase: Phase = .loading
    @State private var objects: [SharedObject] = []
    /// Fix round 1 (Important review finding): how many of the OS-handed providers did NOT become
    /// a `SharedObject` — an unsupported type, or a genuine load/stage failure; both look identical
    /// to the user (nothing renders) unless surfaced. Rendered as a one-line "N item(s) couldn't be
    /// read" whenever non-zero — parity with the composer's own dropped-attachment surfacing.
    @State private var droppedCount = 0
    @State private var note: String = ""
    @State private var locationCapture = LocationCapture()
    /// Task 7 brief: CoreLocation auth prompts can behave hostilely inside a share sheet — a
    /// `.notDetermined` status (never yet asked, in THIS extension process) hides the pin entirely
    /// for v1 rather than risking that prompt. Starts `true` (hidden) until `load()` has actually
    /// checked — never flashes the pin on then immediately hides it.
    @State private var pinHidden = true
    @State private var userId: UUID?
    @State private var staging: StagedFileStore?
    /// Task 7 gate: cached bool from `UserDefaults(suiteName: AppGroup.identifier)`. A MISSING
    /// cache fails open (`true`) — matches `SubscriptionStore.canAddContent`'s own pre-first-check
    /// fail-open default; a present `false` closes Save and shows the inline explainer.
    @State private var canAddContent = true
    /// Plan 15 review: preview bitmaps, decoded once when the share loads (off the main thread,
    /// without ImageIO keeping the full decode) — never in `body`, which re-runs on every
    /// keystroke in the note field.
    @State private var heroThumbnail: UIImage?
    @State private var thumbnails: [URL: UIImage] = [:]
    /// Save → "Saved to Stash", measured here (logged; DEBUG also exposes it to the UI tests).
    @State private var confirmationLatencyMs: Int?
    /// Plan 16: the extension follows the system text size (its own process — the host app's
    /// launch arguments never reach it); at the accessibility sizes some lines wrap further.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Plan 16: lets a tap anywhere on the note's card focus it, not only on its text line.
    @FocusState private var noteFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            // Plan 15 (Will: "let's also ditch the gradient background"): plain paper. The
            // wordmark header below is still the titling convention every app surface uses.
            StashColor.paper.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                StashHeader {
                    // Still one tappable button under the SAME "share.cancel" identifier the UI
                    // tests drive — only the visual changed (round icon vs. bar text). Plan 15
                    // review: hidden (not removed) while saving, so the header keeps its height and
                    // the wordmark doesn't jump when the confirmation appears.
                    Button(action: cancel) {
                        // Will's note: "remove the gray stroke from the X button."
                        CircleIcon(systemImage: "xmark", size: 36, bordered: false)
                    }
                    .buttonStyle(.plain)
                    // Plan 16: named for VoiceOver and the Large Content Viewer; `CircleIcon`
                    // brings the 44 pt target.
                    .stashIconControl("Cancel", systemImage: "xmark")
                    .accessibilityIdentifier("share.cancel")
                    .opacity(showsCancel ? 1 : 0)
                    .disabled(!showsCancel)
                    .accessibilityHidden(!showsCancel)
                }
                .padding(.top, Self.headerExtraInset.top)
                .padding(.horizontal, Self.headerExtraInset.horizontal)
                Group {
                    switch phase {
                    case .loading:
                        StashStatusLine(text: "reading share…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .noSession:
                        noSessionView
                    case .ready, .saving:
                        // Plan 11: the larger hero preview + a note field that can grow to 4 lines
                        // can now exceed the card's visible height — scrolls beneath the pinned
                        // Save bar below instead of clipping.
                        ScrollView {
                            composeBody
                        }
                    case .done(let message):
                        doneView(message)
                    }
                }
            }
            // Plan 11: "make the 'save' button full size ... and pin it to the bottom of the
            // screen." A safe-area inset (not an overlay) so `composeBody`'s ScrollView content
            // never sits underneath it, and so the system's automatic keyboard avoidance pushes it
            // up along with everything else rather than leaving it stranded behind the keyboard.
            .safeAreaInset(edge: .bottom) {
                if showsSaveBar {
                    pinnedSaveBar
                }
            }
        }
        .task { await load() }
    }

    /// Plan 15 (Will: "the share sheet looks a little strange with the logo cut off slightly"):
    /// iOS 26 presents the share sheet with much rounder top corners, and `StashHeader`'s 16/8 pt
    /// insets leave the wordmark (and the round X) right at the corner curves. The extra inset
    /// (header at 26/22 pt) keeps both clear of a corner radius up to ~60 pt, whatever radius the
    /// device's sheet uses. Earlier systems use small sheet corners, so they keep the header
    /// exactly where it was.
    private static var headerExtraInset: (top: CGFloat, horizontal: CGFloat) {
        if #available(iOS 26, *) {
            return (top: 14, horizontal: 10)
        }
        return (top: 0, horizontal: 0)
    }

    private var showsCancel: Bool {
        switch phase {
        case .saving, .done: return false
        case .loading, .noSession, .ready: return true
        }
    }

    private var showsSaveBar: Bool {
        switch phase {
        case .ready, .saving: return true
        case .loading, .noSession, .done: return false
        }
    }

    // MARK: - Loading

    /// Resolves the signed-in user (if any) from the SHARED keychain session — `currentSession` is
    /// a synchronous, non-throwing read of whatever's already persisted (no network refresh
    /// attempt, so this never blocks the card's first paint on a round trip); Task 7's disclosed
    /// no-session behavior below depends on being able to tell "definitely no session at all" apart
    /// from "a session exists but its access token may need a refresh" (the latter is
    /// `ShareIntake`'s own problem to degrade gracefully from, once Save is tapped).
    private func load() async {
        #if DEBUG
        // Plan 7 Task 2: an appex has its own bundle — the app target bundling PP Neue Montreal
        // proves nothing about the extension. This is the extension-side proof, captured from a
        // live share (see task-2-report.md): UIFont.familyNames grouping every bundled weight
        // under its shared name-table-ID-16 typographic family confirms the appex's own
        // `UIAppFonts` + bundled TTFs actually registered the face in THIS process.
        let neueMontrealFamilies = UIFont.familyNames.filter { $0.contains("PP Neue Montreal") }
        print("StashShareExtension font families: \(neueMontrealFamilies)")
        #endif
        let loadStarted = ContinuousClock.now
        guard let resolvedUserId = StashClient.shared.auth.currentSession?.user.id else {
            phase = .noSession
            return
        }
        userId = resolvedUserId
        let store = StagedFileStore(userId: resolvedUserId)
        staging = store
        let result = await ProviderLoader(staging: store).load(from: inputItems)
        let previews = await Self.decodePreviews(for: result.objects)
        heroThumbnail = previews.hero
        thumbnails = previews.tiles
        objects = result.objects
        droppedCount = result.droppedCount
        abandonTracker.track(objects: result.objects, staging: store)
        canAddContent = readGateCache()
        pinHidden = CLLocationManager().authorizationStatus == .notDetermined
        phase = .ready
        Self.log.notice("load: \(result.objects.count) object(s), \(result.droppedCount) dropped, ready after \(Self.ms(since: loadStarted)) ms")
        #if DEBUG
        Self.logMemory("after load")
        #endif
    }

    #if DEBUG
    /// DEBUG measurement aid (plan 15 Task 4): this process's physical footprint and its peak so
    /// far — the number the extension's ~120 MB memory limit is enforced against.
    private static func logMemory(_ moment: String) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let footprint = Double(info.phys_footprint) / 1_048_576
        let peak = Double(info.ledger_phys_footprint_peak) / 1_048_576
        log.notice("memory \(moment, privacy: .public): footprint \(String(format: "%.1f", footprint), privacy: .public) MB, peak \(String(format: "%.1f", peak), privacy: .public) MB")
    }

    /// DEBUG UI-test hook: when the app was launched with `--uitest-share-exit-after-handoff=<ms>`
    /// (it writes this App Group key; every other DEBUG launch removes it), the extension exits
    /// that long after handing the share to the background session — standing in for the system
    /// reclaiming the extension before the upload answers, so the upload can only finish through
    /// the transfer daemon and the app.
    private static var uiTestExitAfterHandoff: Duration? {
        let milliseconds = UserDefaults(suiteName: AppGroup.identifier)?.integer(forKey: "uitest.shareExitAfterHandoffMs") ?? 0
        return milliseconds > 0 ? .milliseconds(milliseconds) : nil
    }
    #endif

    private func readGateCache() -> Bool {
        guard let defaults = UserDefaults(suiteName: AppGroup.identifier) else { return true }
        #if DEBUG
        // UI tests only: the app's DEBUG `--uitest-share-gate-open` launch argument writes this
        // key (and every other DEBUG launch removes it) so the share smokes can exercise Save on
        // the lapsed test account. The server still enforces the gate itself.
        if defaults.bool(forKey: "uitest.shareGateOpen") { return true }
        #endif
        guard defaults.object(forKey: SubscriptionStore.gateCacheKey) != nil else {
            return true   // missing cache -> fail open (plan-1 spec)
        }
        return defaults.bool(forKey: SubscriptionStore.gateCacheKey)
    }

    private static let log = Logger(subsystem: "it.gostash.stash", category: "share")

    private static func ms(since start: ContinuousClock.Instant) -> Int {
        let elapsed = ContinuousClock.now - start
        return Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }

    // MARK: - No session (Task 7 disclosed behavior)

    /// Disclosed no-session behavior: `Outbox`/`StagedFileStore` are per-user-scoped by design (a
    /// shared, user-agnostic directory would leak one account's queued captures into another's —
    /// the exact cross-account bug `Outbox.defaultDirectory`'s own doc comment describes fixing),
    /// so there is no safe "whose Outbox" to queue into without a known user id. Rather than
    /// inventing a placeholder identity, this shows a gentle, non-blocking line and Cancel only —
    /// never a sign-in form (extension-inappropriate scope), never a crash, and no staging/Outbox
    /// write is EVER attempted for a share with no resolvable session. `ProviderLoader` never even
    /// runs in this branch (see `load()` above), so no file is staged that would need cleanup.
    private var noSessionView: some View {
        VStack(spacing: 12) {
            // Art (plan 16): a fixed 24 pt glyph in its 64 pt tile, hidden from VoiceOver — the
            // line below says it.
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(StashType.decorative(.medium, size: 24))
                .foregroundStyle(StashColor.muted)
                .frame(width: 64, height: 64)
                .background(StashColor.paper, in: Rectangle())
                .overlay(Rectangle().strokeBorder(StashColor.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                .accessibilityHidden(true)
            // Identifier lives on this LEAF `Text`, not the container (see `doneView`'s doc
            // comment for why): confirmed LIVE that `.accessibilityElement(children: .ignore)` on
            // a multi-child container, while it's the pattern `CaptureComposerView.pinPreview`
            // uses successfully in the full app, still exposed the Image as a SEPARATE element
            // under the identical identifier once hosted inside THIS extension's
            // `UIHostingController` (itself embedded in Safari's share-sheet process) — an
            // accessibility-bridging difference between the two hosting contexts, not a mistake in
            // that established pattern. A `Text` is inherently one leaf element with nothing to
            // collapse, which sidesteps the question entirely rather than fighting it.
            Text("Sign in to the Stash app to share.")
                .stashFont(.reading)
                .multilineTextAlignment(.center)
                .foregroundStyle(StashColor.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .accessibilityIdentifier("share.noSession")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    #if DEBUG
    private var fontStatus: String {
        let human = StashType.isNeueMontrealAvailable ? "font:neue-montreal" : "font:sf-fallback"
        return "\(human) departure:\(StashType.isDepartureMonoAvailable ? "loaded" : "fallback") jetbrains:\(StashType.isJetBrainsMonoAvailable ? "loaded" : "fallback")"
    }
    #endif

    // MARK: - Compose

    private var composeBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            #if DEBUG
            // Plan 7 Task 2: the extension-side font proof — an appex has its own bundle (can't
            // read the host app's), so bundling PP Neue Montreal in the APP target proves nothing
            // about THIS process. Read by testShareExtensionURLSmoke. DEBUG-only, zero-height so
            // it never shifts the compose card's real layout.
            Text(fontStatus)
                .font(.system(size: 1))   // an invisible 1 pt DEBUG probe, not text (plan 16)
                .foregroundStyle(.clear)
                .frame(height: 0)
                .accessibilityIdentifier("share.fontStatus")
                .accessibilityLabel(fontStatus)
            #endif
            preview
            if droppedCount > 0 {
                droppedMessage
            }
            // Still a vertical-axis TextField (bridges to a UITextView — the UI tests reach it as
            // `textViews["share.note"]`); only `.roundedBorder` swapped for the hairline card.
            // Will's note: "make the 'add a note' text 'optional note...'" — identifier unchanged.
            // Plan 16: the note is reading text (Neue Montreal 17, scaling — it was SF), and its
            // placeholder `muted` (5.38:1; the system placeholder grey is 1.7:1). The whole card
            // takes the tap that focuses it: a text field only answers touches on its own lines, so
            // its 12 pt of padding above and below would be a dead band (simultaneous, so the
            // field's own caret and selection taps are untouched).
            TextField("Add a note", text: $note,
                      prompt: Text("Add a note…").foregroundStyle(StashColor.muted), axis: .vertical)
                .focused($noteFocused)
                .textFieldStyle(.plain)
                .stashFont(.reading)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .hairlineCard()
                .overlay {
                    Rectangle()
                        .strokeBorder(StashColor.spot.opacity(noteFocused ? 1 : 0), lineWidth: 3)
                        .padding(-3)
                        .allowsHitTesting(false)
                }
                .overlay(Rectangle().strokeBorder(noteFocused ? StashColor.ink : StashColor.line, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: StashRadius.object))
                .simultaneousGesture(TapGesture().onEnded { noteFocused = true })
                .accessibilityIdentifier("share.note")
            if case .ready(let location) = locationCapture.state {
                pinPreview(location.label)
            }
            // Save moved to the pinned full-width bar (`pinnedSaveBar`, `.safeAreaInset` on the
            // body) — this row is just the location pin now, and only renders once there's
            // something in it.
            if !pinHidden {
                HStack {
                    pinButton
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 24)
    }

    /// Fix round 1 (Important review finding): "user shared N things, we present M < N — say so."
    /// Counts both an unsupported-UTI provider and a genuine load/stage failure the same way —
    /// either one is a share the user made that silently didn't show up otherwise.
    private var droppedMessage: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").imageScale(.small)
                .accessibilityHidden(true)
            Text(droppedCount == 1 ? "1 item couldn't be read" : "\(droppedCount) items couldn't be read")
                .accessibilityIdentifier("share.dropped")
        }
        .stashFont(.meta)
        .foregroundStyle(StashColor.muted)
    }

    /// Task 7 (Plan 14 fix wave B, #4 — App Review 3.1.1/3.1.3(f): copy must never name an
    /// external purchase destination in-app): "An active subscription is required to save new
    /// items." — neutral, no gostash.it mention. Distinct from the composer's own "Subscribe to
    /// add new items." (that one always has a live `SubscriptionStore` to read from and a
    /// Settings tab one tap away; the extension has neither, but naming the destination — not the
    /// absence of a Settings link — is what Review flags).
    ///
    /// Will's direct request (relayed verbatim): "move the 'subscribe...' messaging to just above
    /// the 'save' button on the share sheet. it seems a little out of place between the shared
    /// item card and the optional note field." Moved out of `composeBody` (the scrolling content
    /// column) into `pinnedSaveBar` (the `.safeAreaInset` bottom bar), directly above the Save
    /// button — see that property for the container change.
    ///
    /// Plan 9 Task 2's tokenized styling is unchanged: `gateBackground` fill, `gateBorder` stroke,
    /// `gateText`, `StashRadius.input`, full-width strip. The negative-`.padding(.vertical: -8)`
    /// workaround that plan 9/fix-round-1 applied to the background/overlay shapes ONLY (not the
    /// HStack itself) is REMOVED here: that workaround existed solely because giving the HStack
    /// real vertical padding, while the strip lived in `composeBody` above `share.note`, shifted
    /// `share.note` down and broke its keyboard focus in `testShareExtensionURLSmoke` (see the old
    /// revision of this comment in history for the full bisection writeup). Now that the strip no
    /// longer sits in the same VStack as `share.note` at all — it's in the separate bottom bar,
    /// with the Save button below it instead — that invariant no longer applies, so real
    /// `.padding(.vertical:)` is used directly and the negative-padding indirection is gone.
    /// Re-verified live: `share.note` keyboard focus is unaffected by this strip's presence either
    /// way now (`testShareExtensionURLSmoke` still exercises `noteField.typeText` and passes).
    private var gateMessage: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "lock.fill").imageScale(.small)
                .accessibilityHidden(true)
            // Leaf-level identifier — see `doneView`'s doc comment for why this container doesn't
            // use `.accessibilityElement(children: .ignore)` the way the full app's equivalent
            // (`CaptureComposerView.pinPreview`) does. Plan 16: the gate palette is 6.95:1.
            Text("An active subscription is required to save new items.")
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("share.gate")
        }
        .stashFont(.secondary)
        .foregroundStyle(StashColor.gateText)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        // Full-width strip, matching the app's own `subscriptionGateMessage`
        // (`CaptureComposerView.swift`) — placed BEFORE `.background`/`.overlay` so those size to
        // this frame, not just the HStack's intrinsic content width.
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous)
                .fill(StashColor.gateBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous)
                .strokeBorder(StashColor.gateBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var preview: some View {
        if objects.isEmpty {
            Text("Nothing to share")
                .stashFont(.reading)
                .foregroundStyle(StashColor.muted)
                .accessibilityIdentifier("share.preview.empty")
        } else if case .url(let url) = objects[0] {
            urlPreview(url, extraCount: objects.count - 1)
        } else if objects.count == 1, case .text(let text) = objects[0] {
            textPreview(text)
        } else {
            filesPreview
        }
    }

    /// Local preview only: the link glyph and derived domain never delay capture with
    /// a favicon or title request. Literal URL text uses the code voice.
    private func urlPreview(_ url: String, extraCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                // Art (plan 16): the favicon stand-in keeps its fixed 14 pt glyph in its 32 pt
                // circle, hidden from VoiceOver (the URL beside it is what's shared).
                Image(systemName: "link")
                    .font(StashType.decorative(.medium, size: 14))
                    .foregroundStyle(StashColor.ink)
                    .frame(width: 32, height: 32)
                    .background(StashColor.fill, in: Rectangle())
                    .overlay(Rectangle().strokeBorder(StashColor.line, lineWidth: 1))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    // Leaf-level identifier — see `doneView`'s doc comment for why this container
                    // doesn't use `.accessibilityElement(children: .ignore)`. Plan 16: the
                    // preview's supporting text (15 pt, scaling); two lines, more at the
                    // accessibility sizes so a long URL isn't cut to its ends.
                    Text(url)
                        .stashFont(.mono(.subheadline))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 6 : 2)
                        .truncationMode(.middle)
                        .accessibilityIdentifier("share.preview.url")
                    if let domain = domain(from: url) {
                        Text(domain)
                            .stashFont(.meta)
                            .foregroundStyle(StashColor.muted)
                            .lineLimit(2)
                    }
                }
            }
            if extraCount > 0 {
                Text("+ \(extraCount) more item\(extraCount == 1 ? "" : "s")")
                    .stashFont(.meta)
                    .foregroundStyle(StashColor.muted)
                    .padding(.leading, 44)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hairlineCard()
    }

    /// Best-effort host for the domain line above — `URLComponents` needs a scheme to populate
    /// `.host`; every real share from Safari/etc. already has one (`https://…`), but a bare
    /// scheme-less string (e.g. typed straight into a test) is retried once with `https://`
    /// prepended rather than just showing nothing.
    private func domain(from urlString: String) -> String? {
        if let host = URLComponents(string: urlString)?.host, !host.isEmpty { return host }
        if let host = URLComponents(string: "https://\(urlString)")?.host, !host.isEmpty { return host }
        return nil
    }

    private func textPreview(_ text: String) -> some View {
        Text(text)
            .stashFont(.secondary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 10 : 5)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hairlineCard()
            .accessibilityIdentifier("share.preview.text")
    }

    private typealias StagedFile = (url: URL, mimeType: String, fileName: String?)

    /// Plan 11 "preview larger": if the first staged item is an image, it gets a full-width hero
    /// (`heroImage`) instead of just another 44pt tile; anything shared alongside it (or a
    /// non-image first item) keeps the original compact row (`compactFileRow`) — "+N" overflow
    /// pattern unchanged.
    private var filesPreview: some View {
        let fileObjects: [StagedFile] = objects.compactMap {
            if case .file(let url, let mimeType, let fileName, _) = $0 { return (url, mimeType, fileName) }
            return nil
        }
        return VStack(alignment: .leading, spacing: 10) {
            if let first = fileObjects.first, first.mimeType.hasPrefix("image/") {
                heroImage
                    .accessibilityLabel(first.fileName ?? "Image")
                let rest = Array(fileObjects.dropFirst())
                if !rest.isEmpty {
                    compactFileRow(rest)
                }
            } else {
                compactFileRow(fileObjects)
            }
        }
        .accessibilityIdentifier("share.preview.files")
    }

    /// The bounded pixel budget for the hero decode — same `CGImageSourceCreateThumbnailAtIndex`
    /// primitive as the 88 px compact tiles, just requested at a bigger target size. ImageIO's
    /// thumbnail generator downsamples DURING decode, so memory stays bounded to this requested
    /// size regardless of the source file's own resolution — a 12MP photo costs the same as a
    /// 1200x1200 one here. 900px covers the widest current device at 3x scale with headroom
    /// (900² × 4 bytes ≈ 3.2MB).
    private nonisolated static let heroMaxPixel: CGFloat = 900
    private nonisolated static let tileMaxPixel: CGFloat = 88

    /// Full-content-width, aspect-fit hero for the first staged image — mirrors the detail sheet's
    /// own hero treatment (`StashRadius.card` + `.stashCardShadow()`, no hairline/fill card behind
    /// it; the image itself is the whole surface). Decoded once in `load()` (`decodePreviews`).
    @ViewBuilder
    private var heroImage: some View {
        if let thumbnail = heroThumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: UIScreen.main.bounds.height * 0.45)
                .clipShape(RoundedRectangle(cornerRadius: StashRadius.card))
                .stashCardShadow()
        }
    }

    private func compactFileRow(_ files: [StagedFile]) -> some View {
        let visible = Array(files.prefix(4))
        let overflow = files.count - visible.count
        return HStack(spacing: 8) {
            ForEach(Array(visible.enumerated()), id: \.offset) { _, file in
                fileThumb(url: file.url, mimeType: file.mimeType, fileName: file.fileName)
            }
            if overflow > 0 {
                // Plan 16: a 12 pt Semibold count (`.caption`, scaling) in a tile that grows with
                // it (at least the 44 pt of its neighbours), and says what it counts.
                Text("+\(overflow)")
                    .stashFont(.custom(.semibold, size: 12))
                    .padding(.horizontal, 4)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(StashColor.wash, in: RoundedRectangle(cornerRadius: StashRadius.object))
                    .accessibilityLabel("\(overflow) more")
                    .accessibilityIdentifier("share.preview.overflow")
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hairlineCard()
    }

    @ViewBuilder
    private func fileThumb(url: URL, mimeType: String, fileName: String?) -> some View {
        if mimeType.hasPrefix("image/"), let thumbnail = thumbnails[url] {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: StashRadius.object))
                .accessibilityLabel(fileName ?? "Image")
        } else {
            // A 44 pt thumbnail tile: its glyph and 8 pt name are a miniature at a fixed scale
            // (`StashType.decorative`; 8 pt is below the 11 pt floor for text), so the tile is
            // one element that tells VoiceOver the whole name (plan 16).
            VStack(spacing: 2) {
                // Each part hidden too: this extension's hosting context doesn't reliably collapse
                // children into the container (see `doneView`), and the tile's label says it all.
                Image(systemName: iconName(for: mimeType))
                    .font(StashType.decorative(.book, size: 17))
                    .imageScale(.large)
                    .accessibilityHidden(true)
                if let fileName {
                    Text(fileName).font(StashType.decorative(.book, size: 8)).lineLimit(1)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 44, height: 44)
            .background(StashColor.wash, in: RoundedRectangle(cornerRadius: StashRadius.object))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(fileName ?? "File")
        }
    }

    /// The preview bitmaps `filesPreview` shows, decoded once, off the main thread: a 900 px hero
    /// for the first file when it's an image, and 88 px tiles for the images among the files the
    /// compact row shows (the first four after the hero, or the first four).
    private static func decodePreviews(for objects: [SharedObject]) async -> (hero: UIImage?, tiles: [URL: UIImage]) {
        let files: [(url: URL, isImage: Bool)] = objects.compactMap {
            if case .file(let url, let mimeType, _, _) = $0 { return (url, mimeType.hasPrefix("image/")) }
            return nil
        }
        guard !files.isEmpty else { return (nil, [:]) }
        let heroURL = files[0].isImage ? files[0].url : nil
        let tileURLs = files.dropFirst(heroURL == nil ? 0 : 1).prefix(4).filter(\.isImage).map(\.url)
        return await Task.detached(priority: .userInitiated) {
            let hero = heroURL.flatMap { makeThumbnail(url: $0, maxPixel: heroMaxPixel) }
            var tiles: [URL: UIImage] = [:]
            for url in tileURLs { tiles[url] = makeThumbnail(url: url, maxPixel: tileMaxPixel) }
            return (hero, tiles)
        }.value
    }

    /// Bounded ImageIO thumbnail decode (the `CGImageSourceCreateThumbnailAtIndex` primitive
    /// `ImagePreparation` also builds on) — this card can preview up to 10 shared images at once,
    /// so decoding each at full size just to render a 44pt thumbnail would defeat the whole point
    /// of staging/downscaling in the first place. The source is opened with
    /// `kCGImageSourceShouldCache: false` (no decoded copy of the full image is kept), while the
    /// thumbnail itself is decoded right here — `kCGImageSourceShouldCacheImmediately`, with no
    /// `ShouldCache: false` beside it to undo that (final wave, T4 review carry) — so this
    /// detached task does the decoding and drawing on the main thread never has to. Never touches
    /// `Data`/`UIImage(contentsOfFile:)`.
    private nonisolated static func makeThumbnail(url: URL, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func iconName(for mimeType: String) -> String {
        if mimeType.hasPrefix("video/") { return "video.fill" }
        if mimeType.hasPrefix("audio/") { return "waveform" }
        if mimeType == "application/pdf" { return "doc.richtext" }
        return "doc.fill"
    }

    // MARK: - Location pin

    private var pinButton: some View {
        Button {
            locationCapture.toggle()
        } label: {
            // The app composer's round icon control, verbatim — active violet when a location is
            // pinned, spinner while resolving (CircleIcon's own `busy` slot replaces the bare
            // ProgressView this used to swap in).
            CircleIcon(systemImage: "mappin",
                       active: pinActive,
                       busy: locationCapture.state == .resolving)
        }
        .buttonStyle(.plain)
        // Plan 16: a toggle for VoiceOver — "Include your location, On/Off" (on while it
        // resolves, too: the user has turned it on) — named like the Add tab's pin.
        .stashIconControl("Include your location", systemImage: "mappin",
                          isOn: pinActive || locationCapture.state == .resolving)
        .accessibilityIdentifier("share.pin")
    }

    private var pinActive: Bool {
        if case .ready = locationCapture.state { return true }
        return false
    }

    private func pinPreview(_ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "mappin.circle.fill")
                .accessibilityHidden(true)
            // Leaf-level identifier — see `doneView`'s doc comment. `CaptureComposerView.pinPreview`
            // (the full app) uses `.accessibilityElement(children: .ignore)` on the container
            // successfully; live-verified here that the SAME pattern does not reliably collapse
            // children in this extension's hosting context, so this copy uses the leaf-identifier
            // form instead rather than carrying the app's pattern into a context it wasn't proven in.
            // Plan 16: wraps (up to three lines) at the accessibility sizes.
            Text("posted from \(label)")
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                .truncationMode(.tail)
                .accessibilityIdentifier("share.pin.preview")
        }
        .stashFont(.meta)
        .foregroundStyle(StashColor.muted)
    }

    // MARK: - Save / Cancel

    /// Will's note: "make the 'save' button full size (standard iOS guidance) and pin it to the
    /// bottom of the screen." Full-width (screen minus 20pt margins), 52pt tall, `StashRadius.input`.
    /// Disabled state (Fix round 1, Will's screenshot: whole-button `.opacity(0.4)` dimmed the fill
    /// AND the label together into a washed lavender pill with an illegible "Save") swaps fill +
    /// label color instead of dimming opacity — `StashColor.wash` fill + `StashColor.muted` text,
    /// no opacity modifier on the label — so the button stays legible while still visibly inert
    /// (never hidden) whenever the gate/empty-share disables it, per Global Constraints. `share.save`
    /// identifier moved here from the old inline capsule.
    ///
    /// Will's direct request (relayed verbatim): "move the 'subscribe...' messaging to just above
    /// the 'save' button on the share sheet." `gateMessage` now renders here, inside this bar,
    /// directly above the Save button (10pt spacing) whenever the gate is closed — see that
    /// property's own doc comment for the container-change/workaround-removal writeup. The bar
    /// stays one `.safeAreaInset` unit, so the keyboard pushes the gate strip and Save button up
    /// together, same as Save alone did before.
    private var pinnedSaveBar: some View {
        VStack(spacing: 10) {
            if !canAddContent {
                gateMessage
            }
            Button {
                Task { await save() }
            } label: {
                ZStack {
                    if phase == .saving {
                        HStack(spacing: 8) {
                            StashCursor()
                            Text("saving…").stashFont(.machine)
                        }
                    } else {
                        // Plan 16: the sheet's one primary action — `textButtonProminent` (Medium
                        // 17, scaling); white on violet-600 5.18:1, `muted` on the disabled wash
                        // 4.86:1. 52 pt at the default size, taller once the word outgrows it.
                        Text("Save")
                            .stashFont(.textButtonProminent)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(canSubmit || phase == .saving ? .white : StashColor.muted)
                .background(
                    canSubmit || phase == .saving ? StashColor.ink : StashColor.fill,
                    in: RoundedRectangle(cornerRadius: StashRadius.input)
                )
            }
            .buttonStyle(.plain)
            .disabled(phase == .saving || !canSubmit)
            .accessibilityIdentifier("share.save")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .background(StashColor.paper)
    }

    private var canSubmit: Bool {
        canAddContent && !objects.isEmpty
    }

    /// Global Constraints "submit() waits ≤2.5s on .resolving" budget — same number
    /// `CaptureViewModel.locationAwaitTimeout` uses (private there, so restated here rather than
    /// exposed as new StashKit surface for one more call site).
    private static let locationAwaitTimeout: TimeInterval = 2.5

    /// How long the confirmation stays up before the sheet dismisses itself. DEBUG: a UI test can
    /// hold it longer (`--uitest-share-confirmation-hold=<ms>` → `uitest.shareConfirmationHoldMs`)
    /// — XCUITest only looks once the host app idles after the tap, which can take longer than
    /// 800 ms on a busy machine.
    private static var confirmationWindow: Duration {
        #if DEBUG
        let held = UserDefaults(suiteName: AppGroup.identifier)?.integer(forKey: "uitest.shareConfirmationHoldMs") ?? 0
        if held > 0 { return .milliseconds(held) }
        #endif
        return .milliseconds(800)
    }

    static let savedMessage = "Saved to Stash"
    static let failedMessage = "Couldn't save — try again"

    /// Plan 15 Task 4 — Save never waits on the network (nor, since the review, on the pin):
    /// 1. every shared object is written to the Outbox (`enqueueForTransfer`) — `.transferring`
    ///    when it can be handed off right away, else `.pending` (without its location if the pin
    ///    is still resolving), so the app sends it as is should this process die first;
    /// 2. with a token valid ≥ 5 min (the common case: a synchronous keychain read) and no pin to
    ///    wait for, the entries go to the shared background session at once
    ///    (`BackgroundCaptureTransfers.start` — request bodies written, tasks started, nothing
    ///    awaited);
    /// 3. "Saved to Stash" shows. Under it, when needed: the pin gets ≤ 2.5 s and its location is
    ///    written into the saved entries; the token is refreshed (≤ 2.5 s); then the hand-off.
    ///    Without a token in time the entries stay in the Outbox for the app;
    /// 4. ~0.8 s after the confirmation, anything the background session couldn't take (another
    ///    process was connected, or a task failed at once) gets one bounded (≤ 6 s) foreground
    ///    send;
    /// 5. `completeRequest`. Whatever is left, the app's drain sends — idempotently.
    /// All of it runs inside an expiring-activity assertion, so the extension isn't suspended
    /// mid-way (a token refresh that rotates the refresh token must reach the keychain).
    private func save() async {
        // Plan 15 review: the guard comes before any side effect — a Save that can't run (or a
        // second one) must not touch the card's state.
        guard phase == .ready, let userId, let staging else { return }
        // Fix round 2 (Important review finding): `markConsumed()` runs right after the guard,
        // before any `await` — see `ShareAbandonTracker`'s "Consumed boundary": from the Save tap
        // on, the Outbox owns every staged file (a swipe during a suspension must not discard
        // them), and if this process dies before the Outbox write, `sweepOrphans` recovers them.
        abandonTracker.markConsumed()
        let tapped = ContinuousClock.now
        phase = .saving
        await Self.keepingProcessAwake("Handing the share to Stash") {
            await handOff(userId: userId, staging: staging, tapped: tapped)
        }
        Self.log.notice("save: completeRequest after \(Self.ms(since: tapped)) ms")
        finish()
    }

    /// Steps 1–4 of `save()`.
    private func handOff(userId: UUID, staging: StagedFileStore, tapped: ContinuousClock.Instant) async {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let intake = ShareIntake(
            userId: userId,
            staging: staging,
            accessToken: { try await StashClient.accessToken(for: userId) }
        )
        let pinResolving = locationCapture.state == .resolving
        var token = Self.currentTransferToken(for: userId)
        let handOffNow = !pinResolving && token != nil

        // 1. Durable first.
        var entries = await intake.enqueueForTransfer(objects, note: trimmedNote.isEmpty ? nil : trimmedNote,
                                                      location: pinResolving ? nil : locationCapture.currentLocation,
                                                      status: handOffNow ? .transferring : .pending)
        guard !entries.isEmpty else {
            // Nothing could be written (a full or unwritable disk): the one outcome that isn't a
            // success. The staged copies go too, so the message stays true — no later sweep
            // quietly saves a share the user was told didn't save.
            for object in objects {
                if case .file(let url, _, _, _) = object { staging.discard(url) }
            }
            phase = .done(Self.failedMessage)
            Self.log.error("save: no object could be written to the Outbox")
            try? await Task.sleep(for: Self.confirmationWindow)
            return
        }
        let persisted = Self.ms(since: tapped)

        // 2–3. Hand off, then confirm — or confirm, then pin/refresh and hand off.
        let transfers = BackgroundCaptureTransfers.shared
        var batch: BackgroundTransferBatch?
        if handOffNow, let token {
            batch = await transfers.start(entries: entries, userId: userId, accessToken: token)
        }
        phase = .done(Self.savedMessage)
        let confirmed = ContinuousClock.now
        confirmationLatencyMs = Self.ms(since: tapped)
        Self.log.notice("save: \(entries.count) of \(objects.count) persisted after \(persisted) ms; confirmation after \(Self.ms(since: tapped)) ms (pin resolving: \(pinResolving), token refresh needed: \(token == nil))")
        if pinResolving, let location = await locationCapture.awaitResolution(timeout: Self.locationAwaitTimeout) {
            entries = await intake.attachLocation(location, to: entries)
            Self.log.notice("save: location added under the confirmation after \(Self.ms(since: tapped)) ms")
        }
        if batch == nil, !entries.isEmpty {
            if token == nil {
                token = await ShareIntake.refreshedTransferToken {
                    let session = try await StashClient.shared.auth.refreshSession()
                    // Never hand one account's captures another account's token.
                    guard session.user.id == userId else { throw CaptureError.badStatus(401) }
                    return session.accessToken
                }
            }
            if let token {
                batch = await transfers.start(entries: entries, userId: userId, accessToken: token)
            } else {
                // They were saved `.pending`: the app sends them the next time it runs.
                Self.log.notice("save: no token in time — \(entries.count) entries left for the app")
            }
        }
        #if DEBUG
        Self.logMemory("after hand-off")
        if let exitAfter = Self.uiTestExitAfterHandoff {
            Self.log.notice("save: UI-test hook — the extension exits \(String(describing: exitAfter), privacy: .public) after the hand-off")
            try? await Task.sleep(for: exitAfter)
            exit(0)
        }
        #endif

        // 4. Hold the confirmation, then catch anything the background session won't deliver.
        try? await Task.sleep(until: confirmed + Self.confirmationWindow, clock: .continuous)
        if let token, let batch {
            let fallback = await transfers.entriesNeedingForegroundSend(in: batch)
            if !fallback.isEmpty {
                let result = await intake.sendInForeground(fallback, accessToken: token)
                Self.log.notice("save: foreground fallback for \(fallback.count) entries — saved \(result.saved), queued \(result.queued), failed \(result.failed)")
            }
            Self.log.notice("save: \(batch.started.count) handed to the background session")
        }
    }

    /// Keeps this extension process from being suspended while `work` runs (bounded by `limit`):
    /// the expiring activity's block holds the assertion until `work` finishes.
    private static func keepingProcessAwake(_ reason: String, limit: TimeInterval = 15,
                                            _ work: () async -> Void) async {
        let finished = DispatchSemaphore(value: 0)
        ProcessInfo.processInfo.performExpiringActivity(withReason: reason) { expired in
            guard !expired else { return }
            _ = finished.wait(timeout: .now() + limit)
        }
        await work()
        finished.signal()
    }

    /// The shared session's access token when it belongs to `userId` and stays valid ≥ 5 minutes
    /// (a synchronous keychain read — no network); `nil` means "refresh first".
    private static func currentTransferToken(for userId: UUID) -> String? {
        guard let session = StashClient.shared.auth.currentSession, session.user.id == userId else { return nil }
        return ShareIntake.usableTransferToken(session.accessToken,
                                               expiresAt: Date(timeIntervalSince1970: session.expiresAt))
    }

    private func doneView(_ message: String) -> some View {
        VStack(spacing: 12) {
            // The completed share is a lit square; the stable message is what VoiceOver reads.
            let saved = message == Self.savedMessage
            Image(systemName: saved ? "checkmark" : "clock.arrow.circlepath")
                .font(StashType.decorative(.semibold, size: 24))
                .foregroundStyle(saved ? StashColor.onSpot : .white)
                .frame(width: 64, height: 64)
                .background(saved ? StashColor.spot : StashColor.ink, in: Rectangle())
                .accessibilityHidden(true)
            // Identifier lives on this LEAF `Text`, not the container. First attempt put
            // `.accessibilityElement(children: .ignore)` + an explicit label on the VStack instead
            // (the exact pattern `CaptureComposerView.pinPreview` uses successfully in the full
            // app) — confirmed LIVE via XCUITest that it did NOT collapse the Image/Text into one
            // element here: reading `.label` on "share.outcome" still threw "Failed to get
            // matching snapshot: Find single matching element. Multiple matching elements found",
            // reproducibly, even after rebuilding to rule out a stale binary. Whatever the exact
            // cause (this view is hosted inside an extension's own `UIHostingController`, itself
            // embedded in Safari's share-sheet process — a different accessibility-bridging
            // context than the full app pinPreview runs in), a leaf `Text` has no children to
            // collapse in the first place, which sidesteps the question entirely.
            Text(message)
                .stashFont(.readingSemibold)
                .foregroundStyle(StashColor.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .accessibilityIdentifier("share.outcome")
                #if DEBUG
                // UI tests: Save → confirmation as measured in this process (XCUITest's own view
                // of it includes waiting for the host app to idle).
                .accessibilityValue(confirmationLatencyMs.map { "\($0) ms" } ?? "")
                #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Cancel delegates entirely to `abandonTracker.discardIfAbandoned()` (final fix wave — BLOCKER
    /// fix). The previous implementation hand-rolled its own loop over `objects` and then called
    /// `markConsumed()`: harmless when Cancel was tapped POST-load (`objects` was fully populated,
    /// so the loop discarded everything, and `markConsumed()` merely blocked the later, redundant
    /// `viewDidDisappear` pass) — but Cancel is ALSO reachable mid-load (`showsCancel` includes
    /// `.loading`), and mid-load `objects` is still empty: the loop discarded nothing, yet
    /// `markConsumed()` still latched `consumed = true`, which made `ShareAbandonTracker.track()`'s
    /// own late-registration catch-up (see that type's "Mid-load staging" doc comment) a permanent
    /// no-op — every file `load()` went on to stage sat on disk unreferenced by any Outbox entry
    /// until the next app launch's `sweepOrphans` recovered them as "orphans" and silently
    /// auto-saved a share the user had explicitly cancelled.
    ///
    /// Delegating instead closes this with no special-casing: POST-load this is byte-identical to
    /// the old behavior, since the tracker's own `objects`/`staging` are exactly this view's
    /// (`track()` copied them over at the end of `load()`). MID-load, `discardIfAbandoned()` finds
    /// nothing yet (same as a mid-load swipe) but latches `discardHasRun`, so the still-running
    /// `load()`'s eventual `track()` call immediately discards everything it just staged instead of
    /// leaving it for `sweepOrphans` to find minutes later. `ShareViewController.viewDidDisappear`'s
    /// own unconditional `discardIfAbandoned()` call afterward stays exactly what it already was: a
    /// safe, idempotent no-op once this method has run.
    private func cancel() {
        abandonTracker.discardIfAbandoned()
        finish()
    }
}

// MARK: - Hairline card (the design system's rectangular sibling of CircleIcon's circle)

private extension View {
    /// The v2 object surface shared by previews and the note field.
    func hairlineCard() -> some View {
        self
            .background(StashColor.surface, in: RoundedRectangle(cornerRadius: StashRadius.object))
            .overlay(RoundedRectangle(cornerRadius: StashRadius.object).strokeBorder(StashColor.line, lineWidth: 1))
    }
}
