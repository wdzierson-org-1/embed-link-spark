import SwiftUI
import StashKit
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation
import CoreTransferable

/// The Add tab (plan 2's launch tab): a resident capture composer — text, detected URLs,
/// photos, camera, and files, all routed through `CaptureViewModel` with an offline Outbox
/// fallback. No navigation destination of its own on success; per the brief's "Correction for
/// implementability", a successful save only switches to the View tab if the user taps the
/// success toast (default: stay in Add and keep capturing).
struct CaptureComposerView: View {
    let userId: UUID
    var switchToView: () -> Void = {}

    @State private var viewModel: CaptureViewModel
    @State private var locationCapture: LocationCapture
    @State private var isSubmitting = false
    @State private var toast: CaptureToast?
    @State private var toastToken = UUID()
    @State private var showLocationAlert = false

    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showCameraPicker = false
    @State private var showFileImporter = false
    @State private var showVoiceRecorder = false
    @FocusState private var editorFocused: Bool

    @Environment(\.scenePhase) private var scenePhase
    @Environment(SubscriptionStore.self) private var subscription

    init(userId: UUID, switchToView: @escaping () -> Void = {}) {
        self.userId = userId
        self.switchToView = switchToView
        // Built as a local `let` (not read back off `self` — `@State`'s wrapper isn't available
        // until after `init` assigns it) so BOTH `_locationCapture` and the closure captured below
        // reference the exact same instance. Same custom-init/State(initialValue:) shape
        // LibraryView uses to build its ItemStore.
        let capture = LocationCapture()
        _locationCapture = State(initialValue: capture)
        // The app is the one place allowed to import UIKit, so it supplies the real
        // UIImage-based `downscale`; StashKit's own default is the identity closure. Task 6:
        // `awaitPendingLocation` bridges to `capture` — StashKit never imports CoreLocation, so
        // this closure is the only place that connects the two.
        _viewModel = State(initialValue: CaptureViewModel(
            userId: userId,
            downscale: downscaleImageData,
            awaitPendingLocation: { [capture] timeout in await capture.awaitResolution(timeout: timeout) }
        ))
    }

    private var canSubmit: Bool {
        !viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !viewModel.attachments.isEmpty
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()
            // Same page-level gradient ambience as the web's capture surface — subtler here
            // so long-form typing stays on a calm background.
            GradientBackdrop(opacity: 0.22)
                .frame(height: 320)
                .ignoresSafeArea(edges: .top)

            // Full-height composer: the editor takes every point between the header and the
            // bottom stack — no dead space (there are no cards beneath the input on this
            // screen, unlike the web's panel-over-grid layout). Everything contextual (URL
            // chip, attachments, gate, location) gathers just above the controls row.
            VStack(alignment: .leading, spacing: 0) {
                StashHeader {
                    if viewModel.pendingOutboxCount > 0 {
                        Text("\(viewModel.pendingOutboxCount)")
                            .font(StashType.semibold(size: 11))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            // .orange has no DESIGN.md token yet.
                            .background(Color.orange, in: Capsule())
                            .accessibilityIdentifier("capture.outboxBadge")
                    }
                }
                editor
                VStack(alignment: .leading, spacing: 10) {
                    if let url = detectFirstURL(in: viewModel.text) {
                        urlChip(url)
                    }
                    if !viewModel.attachments.isEmpty {
                        CaptureAttachmentsRow(attachments: $viewModel.attachments)
                    }
                    if !subscription.canAddContent {
                        subscriptionGateMessage
                    }
                    // Location gets its own line directly above the controls — never inline
                    // between the buttons, where it had no room to breathe.
                    if case .ready(let location) = locationCapture.state {
                        pinPreview(location.label)
                    }
                    bottomBar
                }
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, 8)
            }
        }
        // Keyboard-accessory dismiss: the composer has no reliable "empty" area to tap once the
        // keyboard pushes the attachments row/bottom bar up against it. Device-review fix: a
        // text "Done" button read as a second primary action competing with the violet send
        // button while typing — an icon-only minimize control (present only while the editor is
        // focused, via `.keyboard` placement) reads as a secondary, non-competing affordance.
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    editorFocused = false
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                }
                .accessibilityIdentifier("capture.dismissKeyboard")
                .accessibilityLabel("Hide keyboard")
            }
        }
        .overlay(alignment: .bottom) { toastView }
        .task { await viewModel.drainOutbox() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { Task { await viewModel.drainOutbox() } }
        }
        // Task 6: any resolution failure (fix timeout, geocode came back with nothing nameable, or
        // auth denied) surfaces here — `locationCapture.toggle()` itself never presents UI, it only
        // updates `state`, so this is the one place that turns `.failed` into the brief's alert.
        .onChange(of: locationCapture.state) { _, newState in
            if newState == .failed { showLocationAlert = true }
        }
        .alert("Couldn't find your location", isPresented: $showLocationAlert) {
            // Only offered when the failure was specifically an auth denial (Task 6 brief: "auth
            // denied → same alert + Settings deep-link button") — a plain fix/geocode failure with
            // permission already granted has nothing for Settings to fix.
            if locationCapture.authDenied {
                Button("Open Settings") { openLocationSettings() }
                    .accessibilityIdentifier("capture.pin.openSettings")
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Location unavailable — allow location access in Settings to tag saves with a place.")
        }
        .onChange(of: selectedPhotoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await loadPhotos(items) }
        }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.pdf, .plainText, .movie, .audio, .image],
                      allowsMultipleSelection: true) { result in
            // `handleFileImport` is async now (Task 5's AVAsset duration probe for audio/video) —
            // `fileImporter`'s completion itself can't be, so hop into a `Task`.
            Task { await handleFileImport(result) }
        }
        .fullScreenCover(isPresented: $showCameraPicker) {
            CameraPicker { image in
                if let data = image.jpegData(compressionQuality: 0.9) {
                    // A fresh camera capture has no source filename to carry forward (Task 5:
                    // "camera → nil") — `fileName`/`durationS` stay at their `nil` defaults.
                    viewModel.attachments.append(
                        CaptureAttachment(data: data, fileExtension: "jpg", mimeType: "image/jpeg", kind: .photo))
                }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showVoiceRecorder) {
            VoiceRecorderSheet(userId: userId, viewModel: viewModel) { outcome in
                // `nil` = the sheet was cancelled/dismissed with nothing to report; a real
                // outcome routes through the exact same toast mapping `submit()` uses below.
                if let outcome { showOutcome(outcome) }
            }
        }
    }

    // MARK: - Editor + URL chip

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if viewModel.text.isEmpty {
                Text("Save a thought, a link, anything…")
                    .foregroundStyle(StashColor.muted)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 9)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $viewModel.text)
                .focused($editorFocused)
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier("capture.editor")
        }
        // TextEditor's greedy vertical fill is exactly right here — the composer owns the
        // whole screen between the title and the bottom stack. Full-bleed panel; the small
        // horizontal inset just keeps text off the display edge.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 12)
    }

    /// Composer gate (Task 7): proactively disabled + explained, unlike the web's `UnifiedInputPanel`
    /// (which only toasts "Please subscribe to add new content." on an attempted submit,
    /// `UnifiedInputPanel.tsx:767-772` — never disables Save). The brief calls for this exact
    /// stronger iOS treatment; "post-load only" is inherent, not something checked here —
    /// `SubscriptionStore.canAddContent`'s `isLoading || onTrial || subscribed` (Task 3) can only
    /// ever read `false` after the one-shot `isLoading` flag has already resolved once.
    private var subscriptionGateMessage: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill").imageScale(.small)
            Text("Subscribe to add new items.")
        }
        .font(StashType.bodyMedium(12))
        // .orange has no DESIGN.md token yet.
        .foregroundStyle(.orange)
        .accessibilityIdentifier("capture.subscriptionGate")
    }

    private func urlChip(_ url: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "globe")
            Text(url)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(StashType.meta())
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemFill), in: Capsule())
        .accessibilityIdentifier("capture.urlchip")
    }

    // MARK: - Bottom bar

    // Web button convention (`UnifiedInputPanel.tsx` bottom actions): round iconographic
    // controls with hairline borders, violet active states, and one weighted violet submit.
    // Secondary circles are 40pt (7 × 48pt won't fit a phone row; 40 clears even an SE) with
    // the 48pt save carrying the visual weight.
    private var bottomBar: some View {
        HStack(spacing: 8) {
            PhotosPicker(selection: $selectedPhotoItems, matching: .images) {
                CircleIcon(systemImage: "photo.on.rectangle")
            }
            .accessibilityIdentifier("capture.photosPicker")

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showCameraPicker = true
                } label: {
                    CircleIcon(systemImage: "camera")
                }
                .accessibilityIdentifier("capture.cameraButton")
            }

            Button {
                showFileImporter = true
            } label: {
                CircleIcon(systemImage: "doc.badge.plus")
            }
            .accessibilityIdentifier("capture.fileButton")

            // Hidden only when the device truly has no microphone input at all (`isInputAvailable`
            // — false on some old iPods, never on a real iPhone/simulator). Never gated on
            // permission here: a denied/undetermined mic still opens the sheet, which owns its own
            // inline explainer + Settings link (brief: "never on permission — the sheet handles
            // that").
            if AVAudioSession.sharedInstance().isInputAvailable {
                Button {
                    showVoiceRecorder = true
                } label: {
                    CircleIcon(systemImage: "mic")
                }
                // Task 7: `VoiceRecorderSheet.save()` calls `submitVoiceNote` directly, bypassing
                // this view's own Save button entirely — that button's `.disabled` gate (above)
                // doesn't cover this second submission path, so the gate is applied here instead,
                // at the sheet's only entry point. Disabled rather than hidden (unlike the
                // capability check this `if` is already gated on) so it reads consistently with
                // Save's own visible-but-disabled treatment; the inline message above already
                // explains why.
                .disabled(!subscription.canAddContent)
                .accessibilityIdentifier("capture.voice")
            }

            Spacer(minLength: 8)

            pinButton
            saveButton
        }
        .buttonStyle(.plain)
    }

    // MARK: - Location pin (Task 6)

    private var pinButton: some View {
        let state = locationCapture.state
        let engaged = if case .ready = state { true } else { state == .resolving }
        return Button {
            locationCapture.toggle()
        } label: {
            CircleIcon(systemImage: "mappin", active: engaged, busy: state == .resolving)
        }
        .accessibilityIdentifier("capture.pin")
    }

    private func pinPreview(_ label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "mappin.circle.fill")
            Text("posted from \(label)")
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(StashType.meta())
        .foregroundStyle(StashColor.muted)
        // Without `.ignore` + an explicit label, the Image and Text below are each independently
        // accessible and BOTH inherit the identifier applied below (confirmed live: an XCUITest
        // query for "capture.pin.preview" matched two elements — the icon AND the text, "Multiple
        // matching elements found"). `.ignore` collapses the HStack to one element with an explicit
        // label — NOT `.combine`, which would concatenate the icon's own implicit "Map Pin" label
        // in front of the text this view's own accessibility contract (display-only preview line)
        // and `testLocationPinSmoke`'s "posted from <place>" prefix check both depend on.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("posted from \(label)")
        .accessibilityIdentifier("capture.pin.preview")
    }

    private func openLocationSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private var saveButton: some View {
        Button {
            editorFocused = false
            Task { await submit() }
        } label: {
            CircleSubmitIcon(hot: canSubmit && subscription.canAddContent && !isSubmitting,
                             busy: isSubmitting)
        }
        .disabled(isSubmitting || !canSubmit || !subscription.canAddContent)
        .accessibilityIdentifier("capture.save")
    }

    // MARK: - Actions

    private func submit() async {
        isSubmitting = true
        // Snapshotted BEFORE `submit()` clears `text` (Task 5) — the multi-save notice's
        // description switches on whether a note actually rode the batch's first unit.
        let noteHadContent = viewModel.pendingNoteHasContent
        let outcome = await viewModel.submit()
        isSubmitting = false
        showOutcome(outcome, noteHadContent: noteHadContent)
    }

    /// Shared by `submit()` and the voice-note sheet's Save completion (`submitVoiceNote` returns
    /// the same `CaptureOutcome` type) — one toast-mapping source of truth for both submit paths.
    /// `noteHadContent` only matters for the `count > 1` branch below; the voice-note path (always
    /// `count == 1`) passes `false` as an unused default.
    private func showOutcome(_ outcome: CaptureOutcome, noteHadContent: Bool = false) {
        switch outcome {
        case .saved(let count, let dropped) where dropped == 0 && count > 1:
            // Global Constraints (authoritative, UnifiedInputPanel.tsx:866-873): title + description,
            // switching on whether the batch's note (if any) rode the first item. The composer's
            // toast is a single pill, not a title/description pair, so the two lines are joined —
            // still literally both authoritative strings, just on one `Text`.
            let description = noteHadContent
                ? "Stash keeps one object per item — your note went with the first one."
                : "Stash keeps one object per item, so each got its own."
            show(.saved(message: "Saved as \(count) items\n\(description)", hadDrops: false))
        case .saved(_, let dropped) where dropped == 0:
            show(.saved(message: "Saved", hadDrops: false))
        case .saved(let count, let dropped):
            show(.saved(message: "Saved \(count) — \(dropped) couldn't be saved (too large or failed)",
                        hadDrops: true))
        case .queued(_, let dropped):
            var message = "Offline — will sync (\(viewModel.pendingOutboxCount) pending)"
            if dropped > 0 { message += " — \(dropped) couldn't be saved" }
            show(.queued(message: message))
        case .rejected:
            show(.rejected(message: "Couldn't save — file too large or upload failed"))
        case .nothingToSave:
            break
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            // `Data.self` stays the proven path for the bytes themselves — unchanged from before
            // Task 5, and must keep working even if the filename probe below doesn't.
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let type = item.supportedContentTypes.first
            let ext = type?.preferredFilenameExtension ?? "jpg"
            let mime = type?.preferredMIMEType ?? "image/jpeg"
            // Best-effort ONLY (Task 5): `Data.self` alone carries no filename, and
            // `PickedPhotoFile`'s file-based `FileRepresentation` transfer is a materially
            // different (out-of-process file copy, not in-memory bytes) code path than the
            // proven one above — its failure must never block the attach itself, only leave
            // `fileName` gracefully nil, same philosophy as the AVAsset duration probe below.
            let picked = try? await item.loadTransferable(type: PickedPhotoFile.self)
            if let picked { try? FileManager.default.removeItem(at: picked.url) }
            // This picker only ever matches `.images` (see `bottomBar`'s `PhotosPicker`), so
            // there's never a duration to probe here — only `handleFileImport`'s audio/video
            // branch below does that.
            viewModel.attachments.append(CaptureAttachment(data: data, fileExtension: ext, mimeType: mime,
                                                            kind: .photo, fileName: picked?.suggestedFileName))
        }
        selectedPhotoItems = []
    }

    private func handleFileImport(_ result: Result<[URL], Error>) async {
        guard case .success(let urls) = result else { return }
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else { continue }
            let ext = url.pathExtension.isEmpty ? "bin" : url.pathExtension
            let type = UTType(filenameExtension: ext)
            let mime = type?.preferredMIMEType ?? "application/octet-stream"
            let kind: CaptureAttachment.Kind = (type?.conforms(to: .image) ?? false) ? .photo : .file
            // Probed BEFORE the `defer` above can fire: `stopAccessingSecurityScopedResource()`
            // only runs once this loop iteration's scope exits, which is after this `await`
            // returns — so the security scope is still open for the whole probe, and there's no
            // need to copy the bytes to a temp file first.
            let isAudioOrVideo = type?.conforms(to: .audiovisualContent) ?? false
            let durationS = isAudioOrVideo ? await probeDuration(url: url) : nil
            viewModel.attachments.append(CaptureAttachment(data: data, fileExtension: ext, mimeType: mime,
                                                            kind: kind, fileName: url.lastPathComponent,
                                                            durationS: durationS))
        }
    }

    /// `AVAsset` duration probe for a picked audio/video file (Task 5) — `try?` collapses any
    /// failure (corrupt file, an asset AVFoundation can't actually parse) into a graceful `nil`
    /// rather than blocking the attach; `durationS` is optional everywhere downstream for exactly
    /// this reason. Deviation from the brief's literal `AVAsset(url:)`: the initializer that takes
    /// a URL is declared on `AVURLAsset` (a concrete `AVAsset` subclass) — the base class has none.
    private func probeDuration(url: URL) async -> Double? {
        guard let duration = try? await AVURLAsset(url: url).load(.duration) else { return nil }
        let seconds = duration.seconds
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }

    // MARK: - Toast

    private func show(_ toast: CaptureToast) {
        let token = UUID()
        toastToken = token
        withAnimation { self.toast = toast }
        Task {
            try? await Task.sleep(for: .seconds(3))
            if toastToken == token { withAnimation { self.toast = nil } }
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast.message)
                .font(StashType.bodySemibold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(toast.color, in: Capsule())
                .shadow(radius: 4)
                .padding(.bottom, 20)
                .accessibilityIdentifier("capture.toast")
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onTapGesture {
                    if case .saved = toast { switchToView() }
                    withAnimation { self.toast = nil }
                }
        }
    }
}

private enum CaptureToast: Equatable {
    case saved(message: String, hadDrops: Bool)
    case queued(message: String)
    case rejected(message: String)

    var message: String {
        switch self {
        case .saved(let message, _), .queued(let message), .rejected(let message): message
        }
    }

    // Amber whenever something didn't make it (dropped attachments, offline queueing, or an
    // outright rejection) — green is reserved for a fully clean save (fix round: a partially
    // dropped save must not read as an unqualified success).
    // .orange/.green have no DESIGN.md token yet.
    var color: Color {
        switch self {
        case .saved(_, let hadDrops): hadDrops ? .orange : .green
        case .queued, .rejected: .orange
        }
    }
}

/// Re-encodes oversized photo attachments as JPEG, capped at 4096px on the long side (mirrors
/// the web's upload limits, MediaUploadTypes.ts:26-28). Passed to `CaptureViewModel` as its
/// `downscale` hook so StashKit itself never has to import UIKit. Always re-encodes at the
/// target quality (not just when the long side is over budget) so the hook's contract — "bring
/// this under the size limit" — holds even when the size problem was format (e.g. a lossless
/// PNG) rather than dimensions.
@Sendable private func downscaleImageData(_ data: Data) -> Data {
    guard let image = UIImage(data: data) else { return data }
    let maxDimension: CGFloat = 4096
    let longSide = max(image.size.width, image.size.height)
    let scale = longSide > maxDimension ? maxDimension / longSide : 1
    let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: newSize)
    let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    return resized.jpegData(compressionQuality: 0.85) ?? data
}

/// A `Transferable` wrapper (Task 5) that surfaces the ORIGINAL filename PhotosPicker suggests for
/// a picked asset — `loadTransferable(type: Data.self)` alone carries bytes only, no name.
/// `FileRepresentation`'s file-based import hands back a `ReceivedTransferredFile` whose `.file`
/// URL's last path component is that suggested name (e.g. "IMG_1234.HEIC"). `received.file` is
/// only guaranteed valid for the duration of the `importing` closure, so `url` copies it to a
/// fresh temp path just to keep that name reachable afterward — `loadPhotos` reads only
/// `suggestedFileName` from the result (the bytes it actually attaches come from its own,
/// separate `Data.self` load) and deletes this copy immediately without opening it.
private struct PickedPhotoFile: Transferable {
    let url: URL
    let suggestedFileName: String?

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .item) { SentTransferredFile($0.url) } importing: { received in
            let destination = URL.temporaryDirectory.appending(path: UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return Self(url: destination, suggestedFileName: received.file.lastPathComponent)
        }
    }
}
