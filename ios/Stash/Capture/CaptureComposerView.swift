import SwiftUI
import StashKit
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation

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
    /// Plan 15 6D (M7): picks still loading off the main thread, each shown as a spinner chip.
    @State private var pendingAttachments: [PendingAttachment] = []
    /// Chip thumbnails, decoded once per pick (keyed by `CaptureAttachment.id`; pruned as
    /// attachments leave).
    @State private var thumbnails: [UUID: UIImage] = [:]
    @FocusState private var editorFocused: Bool
    // Task 2 (plan 10 round 2): the tab's own container height, captured from a keyboard-blind
    // measuring layer below — never the height SwiftUI proposes to the composer's own content,
    // which shrinks once the keyboard rises. Used only to compute the card's 2/3 cap; left at 0
    // (cap disabled) for the one frame before the measuring GeometryReader first reports in.
    @State private var containerHeight: CGFloat = 0

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
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
        // Plan 15: photos are prepared inside StashKit (`ImagePreparation` — ImageIO-only, ≤ 2560 px
        // JPEG, orientation applied, metadata dropped) as part of `submit()`, so the app no longer
        // supplies an image hook. Task 6: `awaitPendingLocation` bridges to `capture` — StashKit
        // never imports CoreLocation, so this closure is the only place that connects the two.
        _viewModel = State(initialValue: CaptureViewModel(
            userId: userId,
            awaitPendingLocation: { [capture] timeout in await capture.awaitResolution(timeout: timeout) }
        ))
    }

    private var canSubmit: Bool {
        !viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !viewModel.attachments.isEmpty
    }

    /// Save waits while a pick is still loading, so a capture never silently leaves it behind; the
    /// spinner chip says why, and its × lets the user save without it.
    private var isAddingAttachments: Bool { !pendingAttachments.isEmpty }

    /// Plan 15 final wave: a pick still loading after this long (an iCloud or Photos transfer that
    /// stalled) is given up on with a failure toast — Save must never stay disabled on it.
    private static let pickTimeout: Duration = .seconds(60)

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()
            // Same page-level gradient ambience as the web's capture surface — subtler here
            // so long-form typing stays on a calm background. Final wave: fills the WHOLE tab
            // (not just a 320pt band up top, like the other tabs' washes) — the composer card is
            // capped at 2/3 of the tab's height (Task 2), so a fixed-height band would leave the
            // bottom third of the tab, behind and below the card, as flat white void. Web parity:
            // `Index.tsx`'s page-level wash persists behind its whole capture panel, not just the
            // area above it.
            GradientBackdrop(opacity: 0.22)
                .ignoresSafeArea()

            // Task 2: a dedicated measuring layer, NOT the content column below — `.ignoresSafeArea
            // (.keyboard)` lives here only, so this reader's `geo.size.height` stays the tab's full,
            // unadjusted container height even while the keyboard is up. The real content column
            // below does NOT ignore the keyboard safe area, so its own keyboard-avoidance (the card
            // sliding/shrinking to stay clear of the keyboard) is untouched — only the CAP fed into
            // it below is frozen.
            GeometryReader { geo in
                Color.clear
                    .onAppear { containerHeight = geo.size.height }
                    .onChange(of: geo.size.height) { _, newValue in containerHeight = newValue }
            }
            .ignoresSafeArea(.keyboard)

            // The composer is a floating card (plan 9): the wordmark header stays outside/above
            // it, GradientBackdrop stays behind it, and the editor + attachments/gate/pin +
            // bottom bar all live INSIDE `ComposerCard`, which owns the idle/composing ring.
            VStack(alignment: .leading, spacing: 0) {
                // Add-tab spacing pass (plan 12, Will: "increase the margin on the input panel by
                // 10% … same with the Stash logo"): `StashHeader`'s own horizontal padding (16, a
                // shared Add-tab/share-sheet/Settings/Library component) is left untouched so
                // those other surfaces don't shift — this extra 2pt wrapper is Add-tab-only and
                // brings the wordmark's effective margin to 16 × 1.1 ≈ 18 here without touching
                // the shared component.
                StashHeader {
                    // Will's markup (plan 12 final wave, F1): the in-bar hide-keyboard circle is
                    // gone (it pushed the bottom bar past the card's own width while focused —
                    // measured margin 14→2.7pt on device). Its job moves up here: a plain "Cancel"
                    // text button, top-right of the header row, vertically centered with the
                    // wordmark via `StashHeader`'s own `.center`-aligned HStack, shown only while
                    // the editor is focused. Semantics: cancel = dismiss keyboard only — the draft
                    // is NEVER cleared, matching the composer's existing "stay in Add and keep
                    // capturing" behavior everywhere else. `capture.dismissKeyboard` + the "Cancel"
                    // a11y label are preserved so `testComposerKeyboardAccessory` still finds a
                    // control there (its glyph assertions were updated in place for the new copy).
                    HStack(spacing: 12) {
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
                        if editorFocused {
                            Button {
                                editorFocused = false
                            } label: {
                                Text("Cancel")
                                    .font(StashType.body())
                                    .foregroundStyle(StashColor.violet600)
                            }
                            .accessibilityIdentifier("capture.dismissKeyboard")
                            .accessibilityLabel("Cancel")
                        }
                    }
                }
                .padding(.horizontal, 2)
                // Will's markup (F1c): "add whitespace under the wordmark" — ~10pt more breathing
                // room between the header row and the card's top edge than the bare `StashHeader`
                // padding (`.padding(.bottom, 4)`) gave on its own. A fixed spacer (not `Spacer()`)
                // — this VStack sits in a full-height ZStack, so a flexible `Spacer` here would
                // greedily eat the rest of the tab and shove the card to the bottom of the screen.
                Color.clear.frame(height: 10)
                // `isPanelActive` (web `UnifiedInputPanel.tsx:898-902`): focused OR
                // `hasAnyContent` (`!editorIsEmpty || inputItems.length > 0`) — a non-empty draft
                // OR at least one staged attachment, exactly mirroring the web's boolean shape
                // (fix round 1: a prior version omitted the attachments half of this OR).
                ComposerCard(active: editorFocused || !viewModel.text.isEmpty || !viewModel.attachments.isEmpty
                                     || isAddingAttachments) {
                    VStack(alignment: .leading, spacing: 0) {
                        editor
                        VStack(alignment: .leading, spacing: 10) {
                            if let url = detectFirstURL(in: viewModel.text) {
                                urlChip(url)
                            }
                            if !viewModel.attachments.isEmpty || isAddingAttachments {
                                CaptureAttachmentsRow(
                                    attachments: $viewModel.attachments,
                                    thumbnails: thumbnails,
                                    pending: pendingAttachments,
                                    cancelPending: { placeholder in pendingAttachments.removeAll { $0 == placeholder } }
                                )
                            }
                            if !subscription.canAddContent {
                                subscriptionGateMessage
                            }
                            // Location gets its own line directly above the controls — never
                            // inline between the buttons, where it had no room to breathe.
                            if case .ready(let location) = locationCapture.state {
                                pinPreview(location.label)
                            }
                            bottomBar
                        }
                        // Add-tab spacing pass (plan 12, Will: "increase the padding inside the
                        // input panel by a similar amount (incl. the bottom of the button bar and
                        // left of the button bar)") — this is the one padding shared by every row
                        // in the card's content column INCLUDING `bottomBar`, so scaling it here
                        // covers both the button bar's bottom gap and its leading inset in one
                        // place: horizontal 16 → 18, top 10 → 11, bottom 8 → 9 (×1.1, rounded).
                        .padding(.horizontal, 18)
                        .padding(.top, 11)
                        .padding(.bottom, 9)
                    }
                }
                // Task 2 (plan 10 round 2, Will: "reduce the card size to 2/3 the height of the
                // screen… people will be using the sharing intent to add things the majority of
                // the time anyhow, but let's not make things challenging"). `containerHeight` comes
                // from the keyboard-blind measuring layer above, so this cap never jumps when the
                // keyboard rises — only an UPPER bound (`maxHeight`, not an exact `height`), so the
                // card still shrinks normally to clear the keyboard, it just can never exceed 2/3.
                // `containerHeight == 0` (the one frame before that reader first reports in) leaves
                // the cap off rather than collapsing the card to zero height.
                .frame(maxHeight: containerHeight > 0 ? floor(containerHeight * 2 / 3) : nil, alignment: .top)
                // Add-tab spacing pass (plan 12, Will: "increase the margin on the input panel by
                // 10%") — the card's own outer horizontal margin: 12 × 1.1 = 13.2, rounded to 13.
                .padding(.horizontal, 13)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
        }
        .overlay(alignment: .bottom) { toastView }
        .task {
            // UI-test hook only (`--uitest-import-file=`; always empty in Release builds).
            let syntheticImports = CaptureTestHooks.takeSyntheticImports()
            if !syntheticImports.isEmpty { handleFileImport(.success(syntheticImports)) }
            await viewModel.drainOutbox()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { Task { await viewModel.drainOutbox() } }
        }
        // Plan 14 T3 (Outbox park-on-403): the moment `SubscriptionStore.refresh()` reports
        // `canAddContent == true` again — self-heal trial, a resumed subscription checked on
        // launch/foreground/Settings' own poll, all funnel through this one observed property —
        // any entries a prior 403 `subscription_required` parked get unparked and this composer's
        // own `drainOutbox()` (the gate-strip/outbox-badge state this view already owns) sends
        // them. A FRESH `Outbox` instance over the exact same directory `viewModel`'s own drain
        // uses (`Outbox.defaultDirectory(userId:)`) — this view has no access to `viewModel`'s
        // private instance, but the directory (and its cross-process claim protocol) is the
        // actual shared state, so a second actor instance over it is safe, same as tests and
        // `StashApp`'s own launch sweep already rely on.
        .onChange(of: subscription.canAddContent) { _, canAddContent in
            // Plan 15 final wave: only on the server's definitive yes — the gate also reads open
            // while the status is unknown (fail-open), when unparking would just re-park.
            guard canAddContent, subscription.statusKnown else { return }
            Task {
                let outbox = Outbox(directory: Outbox.defaultDirectory(userId: userId))
                let unparked = await outbox.unparkAll()
                if unparked > 0 {
                    await viewModel.drainOutbox()
                }
            }
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
            // The picks are captured here, so the selection resets at once and the picker opens
            // fresh next time.
            selectedPhotoItems = []
            loadPhotos(items)
        }
        // Thumbnails leave with their attachments (the ×, or a submit clearing the form).
        .onChange(of: viewModel.attachments.map(\.id)) { _, ids in
            thumbnails = thumbnails.filter { ids.contains($0.key) }
        }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.pdf, .plainText, .movie, .audio, .image],
                      allowsMultipleSelection: true) { result in
            handleFileImport(result)
        }
        .fullScreenCover(isPresented: $showCameraPicker) {
            CameraPicker { image in addCameraPhoto(image) }
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
                    // Will's markup (F1d): vertical 9→8 — paired with the container's new 4pt top
                    // inset below, this keeps the placeholder sitting at the same on-screen height
                    // as `TextEditor`'s own caret (see the container comment for the full math).
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $viewModel.text)
                .focused($editorFocused)
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier("capture.editor")
        }
        // TextEditor's greedy vertical fill is exactly right here — it claims whatever room
        // `ComposerCard`'s column gives it above the URL chip/attachments/gate/pin/bottom-bar
        // stack. Final wave: that's no longer "the whole screen" — the card itself is capped at
        // 2/3 of the tab's height (Task 2) — just whatever's left inside the card; the small
        // horizontal inset keeps text off the card's own edge, not the display's.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Will's markup (F1d): "increase the editor's top and leading inset so the
        // placeholder/caret sit ~12pt from the card's top edge and ~16pt from its left edge."
        // BEFORE: `.padding(.horizontal, 12)` only, no explicit top — `TextEditor`'s own built-in
        // `UITextView` insets (textContainerInset top 8, lineFragmentPadding 5) supplied the rest,
        // landing the caret at ≈(17, 8) from the card's corner. First pass landed leading 11
        // (+5 intrinsic = 16) — the wrong direction (17 → 16, less than before). Will asked for
        // MORE, not less: leading 15 (+5 intrinsic = ~20) and top 4 (+8 intrinsic = 12); trailing
        // stays 12 (only the top/leading edges were asked for). Measured against a screenshot
        // post-change to confirm the caret/placeholder sit ~20pt from the card's left edge.
        .padding(.leading, 15)
        .padding(.trailing, 12)
        .padding(.top, 4)
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
        .font(StashType.meta())
        .foregroundStyle(StashColor.gateText)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StashColor.gateBackground, in: RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous)
                .strokeBorder(StashColor.gateBorder, lineWidth: 1)
        )
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
            // iOS 26 device-review fix (plan 12): `.toolbar(placement: .keyboard)` used to render
            // a floating minimize accessory that, on iOS 26, sometimes occluded the violet send
            // button. The in-content replacement that briefly lived HERE (a plain circle in this
            // bar's own left group) turned out to have the same shape of bug at a smaller scale:
            // it widened this row past the card's own column width while focused (measured margin
            // 14→2.7pt on device), so the bottom bar itself started overflowing the card. Final
            // wave (F1 + Will's markup): removed outright — the same job (dismiss the keyboard,
            // keep the draft) now lives as a "Cancel" text button in the header row above
            // (`capture.dismissKeyboard`, see `StashHeader` usage), which can never widen this bar.
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
                .disabled(!subscription.canAddContent && !CaptureTestHooks.opensVoiceGate)
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
            CircleSubmitIcon(hot: canSubmit && subscription.canAddContent && !isSubmitting && !isAddingAttachments,
                             busy: isSubmitting)
        }
        .disabled(isSubmitting || !canSubmit || !subscription.canAddContent || isAddingAttachments)
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

    // MARK: - Attachments (plan 15 6D, M7)
    //
    // Every pick shows a spinner chip at once and loads off the main thread
    // (`ComposerAttachmentLoader`): one transfer per photo, file bytes read in a detached task, the
    // camera's JPEG encoded off-main, and the chip thumbnail decoded once at the chip's pixel size.
    // A pick that fails is reported in a toast — never dropped silently.

    /// Pixel edge the chip thumbnails are decoded at: the chip's point size at this screen's scale.
    private var chipPixels: Int { Int((CaptureAttachmentsRow.chipSize * displayScale).rounded(.up)) }

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        let chipPixels = chipPixels
        loadAttachments(items, noun: "photo") { await ComposerAttachmentLoader.photo($0, chipPixels: chipPixels) }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let chipPixels = chipPixels
            loadAttachments(urls, noun: "file") { await ComposerAttachmentLoader.file(at: $0, chipPixels: chipPixels) }
        case .failure(let error):
            guard (error as? CocoaError)?.code != .userCancelled else { return }
            show(.rejected(message: "Couldn't open that file"))
        }
    }

    private func addCameraPhoto(_ image: UIImage) {
        let chipPixels = chipPixels
        loadAttachments([image], noun: "photo") { await ComposerAttachmentLoader.cameraPhoto($0, chipPixels: chipPixels) }
    }

    /// Shows a pending chip per pick at once, then loads the picks one after another — so they
    /// attach in the order they were picked (the first carries the typed note, `CaptureViewModel`
    /// routing) — each replacing its chip the moment it's ready. A chip the user abandons (its ×)
    /// is skipped, or its late result discarded. Each pick gets at most `pickTimeout`; one that
    /// stalls past it fails (`.timedOut`) instead of holding Save and the picks behind it. The
    /// batch's failures share one toast at the end.
    private func loadAttachments<Source: Sendable>(_ sources: [Source], noun: String,
                                                   load: @escaping @Sendable (Source) async -> AttachmentLoadResult) {
        guard !sources.isEmpty else { return }
        let placeholders = sources.map { _ in PendingAttachment() }
        pendingAttachments += placeholders
        Task {
            var failures: [AttachmentLoadFailure] = []
            for (source, placeholder) in zip(sources, placeholders) {
                guard pendingAttachments.contains(placeholder) else { continue }
                let result = await withDeadline(Self.pickTimeout, fallback: .failure(.timedOut)) { await load(source) }
                guard let index = pendingAttachments.firstIndex(of: placeholder) else { continue }
                pendingAttachments.remove(at: index)
                switch result {
                case .success(let loaded):
                    thumbnails[loaded.attachment.id] = loaded.thumbnail
                    viewModel.attachments.append(loaded.attachment)
                case .failure(let failure):
                    failures.append(failure)
                }
            }
            if let message = AttachmentLoadFailure.toastMessage(for: failures, noun: noun) {
                show(.rejected(message: message))
            }
        }
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
    // .orange is a bare literal with no DESIGN.md warn/amber token yet (plan-11 wrap fold:
    // only added `success`, which covers the green case below).
    var color: Color {
        switch self {
        case .saved(_, let hadDrops): hadDrops ? .orange : StashColor.success
        case .queued, .rejected: .orange
        }
    }
}
