import CoreGraphics
import CoreLocation
import ImageIO
import StashKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The real share-extension compose card (Task 7) — replaces Task 5's placeholder. Compact,
/// type-appropriate preview, an optional note, an optional location pin (reusing the app's own
/// `LocationCapture` state machine — see `project.yml`'s doc comment on why that file is shared
/// into this target rather than re-implemented), and a Save button that always resolves to a
/// visible outcome ("Saved to Stash" / "Saved — will sync") before auto-dismissing — Global
/// Constraints: the user ALWAYS sees success, never an error, never a stuck spinner.
struct ShareComposeView: View {
    let extensionContext: NSExtensionContext?
    /// Owned by `ShareViewController` (persists across this struct's own re-creations) — see
    /// `ShareAbandonTracker`'s own doc comment for the abandon/discard contract this implements.
    let abandonTracker: ShareAbandonTracker

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

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()
            // Same page-level gradient ambience as the app's own composer (CaptureComposerView) —
            // the share card is a pocket edition of that surface, not an OS-default form. Replaces
            // the previous NavigationStack + inline "Stash" title; the wordmark header below is
            // the titling convention every app surface already uses.
            GradientBackdrop(opacity: 0.25)
                .frame(height: 240)
                .ignoresSafeArea(edges: .top)

            VStack(alignment: .leading, spacing: 0) {
                StashHeader {
                    if showsCancel {
                        // Still one tappable button under the SAME "share.cancel" identifier the
                        // UI tests drive — only the visual changed (round icon vs. bar text).
                        Button(action: cancel) {
                            CircleIcon(systemImage: "xmark", size: 36)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Cancel")
                        .accessibilityIdentifier("share.cancel")
                    }
                }
                Group {
                    switch phase {
                    case .loading:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .noSession:
                        noSessionView
                    case .ready, .saving:
                        composeBody
                    case .done(let message):
                        doneView(message)
                    }
                }
            }
        }
        .task { await load() }
    }

    private var showsCancel: Bool {
        switch phase {
        case .saving, .done: return false
        case .loading, .noSession, .ready: return true
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
        guard let resolvedUserId = StashClient.shared.auth.currentSession?.user.id else {
            phase = .noSession
            return
        }
        userId = resolvedUserId
        let store = StagedFileStore(userId: resolvedUserId)
        staging = store
        let result = await ProviderLoader(staging: store).load(from: extensionContext)
        objects = result.objects
        droppedCount = result.droppedCount
        abandonTracker.track(objects: result.objects, staging: store)
        canAddContent = readGateCache()
        pinHidden = CLLocationManager().authorizationStatus == .notDetermined
        phase = .ready
    }

    private func readGateCache() -> Bool {
        guard let defaults = UserDefaults(suiteName: AppGroup.identifier),
              defaults.object(forKey: SubscriptionStore.gateCacheKey) != nil
        else { return true }   // missing cache -> fail open (plan-1 spec)
        return defaults.bool(forKey: SubscriptionStore.gateCacheKey)
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
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(StashColor.muted)
                .frame(width: 64, height: 64)
                .background(Color(.systemBackground), in: Circle())
                .overlay(Circle().strokeBorder(StashColor.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
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
                .font(StashType.body())
                .multilineTextAlignment(.center)
                .foregroundStyle(StashColor.muted)
                .padding(.horizontal, 24)
                .accessibilityIdentifier("share.noSession")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Compose

    private var composeBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            #if DEBUG
            // Plan 7 Task 2: the extension-side font proof — an appex has its own bundle (can't
            // read the host app's), so bundling PP Neue Montreal in the APP target proves nothing
            // about THIS process. Read by testShareExtensionURLSmoke. DEBUG-only, zero-height so
            // it never shifts the compose card's real layout.
            Text(StashType.isNeueMontrealAvailable ? "font:neue-montreal" : "font:sf-fallback")
                .font(StashType.regular(size: 1))
                .frame(height: 0)
                .accessibilityIdentifier("share.fontStatus")
                .accessibilityLabel(StashType.isNeueMontrealAvailable ? "font:neue-montreal" : "font:sf-fallback")
            #endif
            preview
            if droppedCount > 0 {
                droppedMessage
            }
            if !canAddContent {
                gateMessage
            }
            // Still a vertical-axis TextField (bridges to a UITextView — the UI tests reach it as
            // `textViews["share.note"]`); only `.roundedBorder` swapped for the hairline card.
            TextField("Add a note…", text: $note, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .hairlineCard()
                .accessibilityIdentifier("share.note")
            if case .ready(let location) = locationCapture.state {
                pinPreview(location.label)
            }
            HStack {
                if !pinHidden { pinButton }
                Spacer()
                saveButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Fix round 1 (Important review finding): "user shared N things, we present M < N — say so."
    /// Counts both an unsupported-UTI provider and a genuine load/stage failure the same way —
    /// either one is a share the user made that silently didn't show up otherwise.
    private var droppedMessage: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").imageScale(.small)
            Text(droppedCount == 1 ? "1 item couldn't be read" : "\(droppedCount) items couldn't be read")
                .accessibilityIdentifier("share.dropped")
        }
        .font(StashType.meta())
        .foregroundStyle(StashColor.muted)
    }

    /// Task 7: "Subscribe on gostash.it to add items" — a cached-false gate, unlike the composer's
    /// own "Subscribe to add new items." (that one always has a live `SubscriptionStore` to read
    /// from and a Settings tab one tap away; the extension has neither, so the copy points
    /// somewhere actionable instead).
    ///
    /// Plan 9 Task 2: tokenized gate strip — `gateBackground` fill, `gateBorder` stroke, `gateText`,
    /// `StashRadius.input` — but the box's VERTICAL padding is applied to the `.background`/
    /// `.overlay` shapes only (via negative `.padding`, which expands a shape past its parent's
    /// reported bounds without growing what the HStack reports upward), NOT to the HStack itself.
    /// Live-verified regression, same "this hosting context behaves differently from the full app"
    /// category as `pinPreview`'s/`doneView`'s own doc comments: giving the HStack real
    /// `.padding(.vertical:)` — which pushes `share.note` a few points further down the card, same
    /// as the full app's `CaptureComposerView.subscriptionGateMessage` safely does — made
    /// `testShareExtensionURLSmoke`'s very next step (`noteField.typeText`) fail 4/4 runs with
    /// "Neither element nor any descendant has keyboard focus", while the exact same box with only
    /// HORIZONTAL HStack padding (note's own Y unchanged) passed 3/3. Root cause not fully
    /// isolated (not keyboard-avoidance — `.ignoresSafeArea(.keyboard)` didn't fix it either) but
    /// the Y-shift correlation was clean and reproducible across 7 bisection runs; this sidesteps
    /// it entirely rather than shipping a regression.
    private var gateMessage: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill").imageScale(.small)
            // Leaf-level identifier — see `doneView`'s doc comment for why this container doesn't
            // use `.accessibilityElement(children: .ignore)` the way the full app's equivalent
            // (`CaptureComposerView.pinPreview`) does.
            Text("Subscribe on gostash.it to add items")
                .accessibilityIdentifier("share.gate")
        }
        .font(StashType.meta())
        .foregroundStyle(StashColor.gateText)
        .padding(.horizontal, 14)
        // Invariant (fix round 1): this -8pt overflow must stay < composeBody's own VStack
        // `spacing: 14` (line 181) — it must not visually reach far enough to overlap the
        // sibling above/below, only fill the breathing room that spacing already reserves.
        .background(
            RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous)
                .fill(StashColor.gateBackground)
                .padding(.vertical, -8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous)
                .strokeBorder(StashColor.gateBorder, lineWidth: 1)
                .padding(.vertical, -8)
        )
    }

    @ViewBuilder
    private var preview: some View {
        if objects.isEmpty {
            Text("Nothing to share")
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

    /// "favicon+URL line" (brief): a link glyph standing in for a real per-site favicon — fetching
    /// one live would add a network dependency (and a visible delay) to a card whose whole point is
    /// an instant, offline-safe preview; disclosed simplification, not an oversight. The glyph
    /// wears the app's violet toggled-circle treatment (`CircleIcon`'s active state) instead of
    /// the stock blue SF Symbol.
    private func urlPreview(_ url: String, extraCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(StashColor.violet600)
                    .frame(width: 34, height: 34)
                    .background(StashColor.violet600.opacity(0.12), in: Circle())
                    .overlay(Circle().strokeBorder(StashColor.violet300, lineWidth: 1))
                // Leaf-level identifier — see `doneView`'s doc comment for why this container
                // doesn't use `.accessibilityElement(children: .ignore)`.
                Text(url)
                    .font(StashType.body())
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .accessibilityIdentifier("share.preview.url")
            }
            if extraCount > 0 {
                Text("+ \(extraCount) more item\(extraCount == 1 ? "" : "s")")
                    .font(StashType.meta())
                    .foregroundStyle(StashColor.muted)
                    .padding(.leading, 44)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hairlineCard()
    }

    private func textPreview(_ text: String) -> some View {
        Text(text)
            .font(StashType.body())
            .lineLimit(5)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hairlineCard()
            .accessibilityIdentifier("share.preview.text")
    }

    private var filesPreview: some View {
        let fileObjects: [(url: URL, mimeType: String, fileName: String?)] = objects.compactMap {
            if case .file(let url, let mimeType, let fileName, _) = $0 { return (url, mimeType, fileName) }
            return nil
        }
        let visible = Array(fileObjects.prefix(4))
        let overflow = fileObjects.count - visible.count
        return HStack(spacing: 8) {
            ForEach(Array(visible.enumerated()), id: \.offset) { _, file in
                fileThumb(url: file.url, mimeType: file.mimeType, fileName: file.fileName)
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(StashType.bodySemibold(12))
                    .frame(width: 44, height: 44)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("share.preview.overflow")
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hairlineCard()
        .accessibilityIdentifier("share.preview.files")
    }

    @ViewBuilder
    private func fileThumb(url: URL, mimeType: String, fileName: String?) -> some View {
        if mimeType.hasPrefix("image/"), let thumbnail = makeThumbnail(url: url, maxPixel: 88) {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            VStack(spacing: 2) {
                Image(systemName: iconName(for: mimeType)).imageScale(.large)
                if let fileName {
                    Text(fileName).font(StashType.regular(size: 8)).lineLimit(1)
                }
            }
            .frame(width: 44, height: 44)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    /// Bounded ImageIO thumbnail decode (same `CGImageSourceCreateThumbnailAtIndex` primitive
    /// `StagedFileStore.stageDownscaledImage` uses) — this card can preview up to 10 shared images
    /// at once, so decoding each at full size just to render a 44pt thumbnail would defeat the
    /// whole point of staging/downscaling in the first place. Never touches `Data`/`UIImage(contentsOfFile:)`.
    private func makeThumbnail(url: URL, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
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
        .accessibilityIdentifier("share.pin")
    }

    private var pinActive: Bool {
        if case .ready = locationCapture.state { return true }
        return false
    }

    private func pinPreview(_ label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "mappin.circle.fill")
            // Leaf-level identifier — see `doneView`'s doc comment. `CaptureComposerView.pinPreview`
            // (the full app) uses `.accessibilityElement(children: .ignore)` on the container
            // successfully; live-verified here that the SAME pattern does not reliably collapse
            // children in this extension's hosting context, so this copy uses the leaf-identifier
            // form instead rather than carrying the app's pattern into a context it wasn't proven in.
            Text("posted from \(label)")
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityIdentifier("share.pin.preview")
        }
        .font(StashType.meta())
        .foregroundStyle(StashColor.muted)
    }

    // MARK: - Save / Cancel

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            ZStack {
                if phase == .saving {
                    ProgressView().tint(.white)
                } else {
                    Text("Save").font(StashType.bodySemibold())
                }
            }
            .frame(minWidth: 64)
            .frame(height: 44)
            .padding(.horizontal, 14)
            .foregroundStyle(saveIsHot ? .white : StashColor.faint)
            .background(saveIsHot ? StashColor.violet600 : Color(.systemBackground), in: Capsule())
            .overlay(Capsule().strokeBorder(saveIsHot ? StashColor.violet600 : StashColor.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(phase == .saving || !canAddContent || objects.isEmpty)
        .accessibilityIdentifier("share.save")
    }

    /// `CircleSubmitIcon`'s weighted/resting split, stretched into a capsule (a share card wants
    /// the word "Save", not a paperplane): violet-filled while a tap would actually save — and
    /// while the save runs, so the spinner sits on violet — the resting white/gray capsule
    /// otherwise, never dimmed (web: `disabled:opacity-100`).
    private var saveIsHot: Bool {
        phase == .saving || (canAddContent && !objects.isEmpty)
    }

    /// Global Constraints "submit() waits ≤2.5s on .resolving" budget — same number
    /// `CaptureViewModel.locationAwaitTimeout` uses (private there, so restated here rather than
    /// exposed as new StashKit surface for one more call site).
    private static let locationAwaitTimeout: TimeInterval = 2.5

    private func save() async {
        // Fix round 2 (Important review finding): `markConsumed()` is the FIRST statement here,
        // before any `await` — including `awaitResolution` below, which can itself suspend for up
        // to `locationAwaitTimeout`. The Save TAP is the intent boundary, not whatever
        // `ShareIntake.submit` does internally afterward: a swipe-to-dismiss landing during that
        // suspension used to find `consumed` still `false`, so `viewDidDisappear` discarded the
        // staged files out from under this still-running `save()` Task — which then found its own
        // file missing (`StagedFileStore.fileSize(of:)` -> nil -> treated as 0 -> passed the
        // direct-send-limit check -> the upload itself threw), fell back to a queued Outbox entry
        // pointing at a path that no longer existed (permanently un-drainable), and still reported
        // "Saved — will sync" to the user. Calling this before any suspension point closes that
        // window entirely: from here on, EITHER `ShareIntake` owns every staged file's lifecycle
        // (discards on a successful direct send, deliberately RETAINS a file it queues) OR — if
        // this process dies before `submit` finishes — the files are left on disk with no Outbox
        // entry, which `sweepOrphans` recovers on next launch. Both outcomes match the user's
        // already-expressed intent to save; `abandonTracker` must never discard out from under
        // either one, including during the 0.8s outcome window below and the `viewDidDisappear`
        // teardown `completeRequest` triggers afterward. See `ShareAbandonTracker`'s own doc
        // comment.
        abandonTracker.markConsumed()
        guard let userId, let staging else { return }
        phase = .saving

        let location = await locationCapture.awaitResolution(timeout: Self.locationAwaitTimeout)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        let intake = ShareIntake(
            userId: userId,
            staging: staging,
            accessToken: { try await StashClient.shared.auth.session.accessToken }
        )
        let result = await intake.submit(objects, note: trimmedNote.isEmpty ? nil : trimmedNote, location: location)

        let message: String
        if result.queued > 0 {
            message = "Saved — will sync"
        } else if result.saved > 0 {
            message = "Saved to Stash"
        } else {
            message = "Couldn't save — try again"
        }
        phase = .done(message)
        try? await Task.sleep(for: .seconds(0.8))
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    private func doneView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: message == "Saved to Stash" ? "checkmark" : "clock.arrow.circlepath")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                // .orange has no DESIGN.md token yet.
                .background(message == "Saved to Stash" ? AnyShapeStyle(StashColor.violet600) : AnyShapeStyle(.orange), in: Circle())
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
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
                .font(StashType.bodySemibold())
                .accessibilityIdentifier("share.outcome")
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
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}

// MARK: - Hairline card (the design system's rectangular sibling of CircleIcon's circle)

private extension View {
    /// Solid background on a gray hairline with a soft shadow — the same treatment `CircleIcon`
    /// gives its circles, applied to every rectangular surface on this card (previews, note
    /// field) so the whole card reads as one family instead of stock `.roundedBorder` chrome.
    func hairlineCard() -> some View {
        self
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(StashColor.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
}
