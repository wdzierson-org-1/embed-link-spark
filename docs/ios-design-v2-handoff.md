# iOS design v2 — simulator handoff

## Integrated app

The October 10 update is implemented on `codex/ios-design-v2`, based on local main
`d9c2530c`. The primary checkout is `/Users/will/Appdev/embed-link-spark`.
The simulator gallery contains real native captures using the review account.

## October 10 — share toast and web alignment

- Main navigation is **View, Ask, Add, Settings**; View opens by default.
- Detail presents URL, title, description, media, source tabs, notes, details, and sharing.
  Source tabs, sharing controls, sticky-note typography, and the location glyph match the web.
- The share extension floats a rounded white toast over the sending app, with an explicit
  **Save** button. Swipe upward or tap **More options** for location, public sharing, and dictation.
- **Share this stash** defaults off for each new share. Its choice is written into every item’s
  durable capture payload, including offline captures; notes attach to the first item in a batch.
- Location consent persists per account across Add and the extension until switched off.
  Coordinates are only kept in memory; stale fixes and revoked consent are rejected. New fixes
  publish before reverse geocoding. A resolving location gets a separate bounded 2.5-second
  chance to attach after saving, without keeping the toast open. Permission or GPS failures
  never block saving; a missing fix means that particular capture has no location.
- Preview work has a **500 ms overall deadline**. Supplied titles render immediately. On a
  connected, unconstrained, non-metered path, links try the existing fast metadata API and
  images try existing image analysis with a small JPEG. Apple Vision extracts text locally from
  images or a PDF’s first page. Offline OCR is labeled as observed text, not a guessed book identity.
  Preview work never creates an item or uploads to storage, and never delays Save. Normal
  enrichment still runs after capture. Network eligibility is a cost/path check, not a speed test.
- Save confirms after local durability, dismisses after a 500 ms confirmation, and transfers
  independently. Partial local-write failures stay visible with an accurate count.
- **Dictate a note** focuses the note field and explains the keyboard microphone. It produces
  note text; it does not attach an audio recording. Share extensions cannot record microphone
  audio directly under Apple’s [extension restrictions](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionOverview.html).
- The interactive sign-in preview now closes after successful authentication and starts normal
  session observation. This fixes the preview overlay that previously hid successful logins.

Presentation uses Apple’s documented `NSExtensionShareWantsFullScreenPresentation` opt-in,
verified in Safari. See [What’s New in Sharing](https://developer.apple.com/videos/play/tech-talks/210/).

Verification: 928 StashKit tests passed, covering durable public/private payloads, persistent
consent and stale-fix rejection, preview rules, and deadline cancellation. Native UI tests passed
for preview sign-in/session restoration/tab order and the real Safari share flow: expansion by
tap/swipe, public on/off, note entry, confirmation within 500 ms, dismissal, and exactly one private
server item. Test-created items were removed. The read-only NASA detail check passed for
URL/title/source/notes/details/sharing order, source switching, and keyboard dismissal. The AX3 share check also passed: first-tap note
focus, pinned Save above the keyboard, touch targets, and the accessibility audit. Physical-device
GPS, gyroscope feel, and keyboard
microphone input still require an iPhone check.

Logs/results:

- `/private/tmp/stash-share-full-unit-unrestricted.log`
- `/private/tmp/stash-share-build-final.log`
- `/private/tmp/stash-share-ui.xcresult`
- `/private/tmp/stash-share-acceptance-v2-ui.xcresult`
- `/private/tmp/stash-share-large-v4-ui.xcresult`
- `/private/tmp/stash-share-final-ui.xcresult` (share save, read-only preview and tab labels passed;
  legacy detail anatomy could not find its pre-seeded `UITEST-FIXTURE: link one`)
- `/private/tmp/stash-design-detail-final-v2-ui.xcresult` (existing NASA review fixture, passed)

## Review origin

- Branch: `codex/ios-design-v2`
- Checkout: `/Users/will/Documents/ChatGPT/Stash/worktrees/ios-design-v2`
- Base: main `07208635`; includes the stabilized iOS app and its subsequent citation-edit fix.
- Visual reference: `app-redesign-v2` at `a0969463`, October 7 `DESIGN-v2.md`.
- Dedicated simulator: **Stash Design v2**, iPhone 17 Pro, iOS 26.5.
- Simulator ID: `B6845555-0DE1-40FB-A77F-FF411946AA5F`.

## What changed

Paper, white, black ink and lime replace the purple gradient and type tints. The ST4SH
wordmark, A/4 symbol and charcoal icon match the web redesign. Montreal carries human
words; Departure Mono carries short machine labels; JetBrains Mono carries URLs and code.
Cards use 2 pt corners, controls square edges, and floating windows a hard print shadow.

The native pass covers sign-in/sign-up, Add, library/search, cards and fallback artwork,
item detail, Ask/history, settings, onboarding, voice capture, splash, and share compose.
The library uses two independently packed masonry columns at normal text sizes and one at accessibility sizes. Cards retain the web’s fixed left-to-right chronological assignment.
The existing backend, capture queue, editing, chat streaming and session flows are preserved.

### Native adaptations

- The tab bar, system pickers and modal presentation remain native iOS.
- Cards remain one tap target opening their detail sheet; mobile has no nested card editor.
- Settings keeps account/phone/subscription actions in a flat numbered list.
- Details starts collapsed, retaining the native information hierarchy and existing behavior.
- Reading text stays at 17 pt, supporting text at 15 pt; machine labels start at 11 pt and
  scale with Dynamic Type. Departure Mono has one weight; other text honors Bold Text.
- The current mobile pass uses truthful cursor status for enrichment. The web's elaborate
  pixel-resolution effect and transient completion/decryption on each arriving card remain
  a follow-up; the native splash has its own reduced-motion-aware decrypt sequence.

## Masonry and motion follow-up

- **View:** fixed left/right masonry assignment from newest to oldest. Card height advances only
  its own column; VoiceOver retains the same chronological sequence. Paging remains demand-driven.
  Hero images load within a one-screen margin and unload farther away while retaining their measured height.
- **Sign-in:** the marketing header’s lime field, dot/stipple texture and liquid ASCII ramp,
  backed by a native particle/grid fluid simulation. Core Motion uses both gravity axes and
  gyroscope angular velocity: turning the phone splashes in that direction, and holding it
  tilted or inverted lets the liquid collect at the lowered edge. The form stays still.
  Nothing is recorded or uploaded.
- **Motion budget:** at most 600 particles, 30 updates/second (15 in Low Power Mode). Sensor
  updates stop when the app becomes inactive, the screen disappears, or a field gains focus.
  Reduce Motion freezes the pool and the cursor. The simulator has a gentle idle current.
- **Ask:** one larger rotating cursor marks thinking/searching/writing, then stops on completion,
  interruption or failure. Status words remain stable for VoiceOver.
- [12-second motion preview](ios-design-v2/ascii-motion.mp4): actual simulator recording with
  explicitly injected left/right motion, compiled only in DEBUG. Physical sensor response still
  needs an iPhone check; the simulator cannot reproduce a real gyroscope.

The fluid model ports the web’s FLIP particle/grid method with bounded particles and pressure
iterations. Unit checks cover motion direction, settling, and containment under large forces.
A desktop benchmark measured 546 particles at 19.69 ms per frame in Debug; an optimized build
measured 750 particles at 0.54 ms per frame. These are simulation costs, not device frame-rate claims.

Core Motion follows Apple’s [start/stop lifecycle](https://developer.apple.com/documentation/coremotion/cmmotionmanager/startdevicemotionupdates())
and reads the fused [rotation rate](https://developer.apple.com/documentation/coremotion/cmdevicemotion/rotationrate).

### October 8 — gyroscope follow-up

The login backdrop retains the homepage's 13 pt grid, 11 pt Departure Mono, density/speed
character ramp, lime field and 35% pool fill. Particle footprints reconstruct the fuller web
water using the same 600-particle native budget. Dot fade and noise-dithered spheres now follow
the homepage texture. The motion mapper preserves upward/sideways gravity, adds a directional
angular impulse, smooths sensor jitter, and fades a weak downward pull in only when held flat.

`--uitest-preview-signin` is a DEBUG-only standalone login preview that leaves the saved
session untouched until the user explicitly signs in. Successful authentication now exits the preview. Pair it with `--uitest-pool-motion-demo` to demonstrate clockwise/counterclockwise
samples in the simulator. These samples pass through the same mapper as the physical sensor.
Remove the launch arguments to return to the saved account. Actual sensor feel still needs an iPhone.

Verified on October 8:

- **904 StashKit tests passed**, including ten motion-mapper cases and two motion-to-fluid
  integration cases within that set. Full log: `/private/tmp/stash-ios-gyro-unit-unsandboxed.log`.
- **Six simulator UI checks passed**: opposite tilts, opposite gyroscope rates, inverted
  water moving upward, Reduce Motion, freezing while typing, and saved-session preservation.
  Results: `/private/tmp/stash-ios-gyro-ui-final.xcresult`.
- App and embedded share extension build passed: `/private/tmp/stash-ios-gyro-final-build.log`.
- New motion clip uses simulated gravity and angular-velocity samples; screenshots verify
  the actual native renderer. This does not certify physical iPhone sensor response or frame rate.

The first full unit run hit sandbox restrictions in unrelated Keychain/file-type checks;
running with the required macOS service access passed all 904. Two initial UI checks cropped
outside the liquid; they now inspect exposed wave pixels and passed in the final six-test run.

## Run it again

```sh
cd /Users/will/Appdev/embed-link-spark/ios
xcodegen generate
xcodebuild build -project Stash.xcodeproj -scheme Stash \
  -destination 'platform=iOS Simulator,id=B6845555-0DE1-40FB-A77F-FF411946AA5F' \
  -derivedDataPath /private/tmp/stash-ios-main-ui-build
xcrun simctl install B6845555-0DE1-40FB-A77F-FF411946AA5F \
  /private/tmp/stash-ios-main-ui-build/Build/Products/Debug-iphonesimulator/Stash.app
xcrun simctl launch B6845555-0DE1-40FB-A77F-FF411946AA5F it.gostash.stash
open /Applications/Xcode.app/Contents/Applications/DeviceHub.app
```

In Xcode 27's **Device Hub**, select **Stash Design v2**. The name-only `open -a Simulator`
resolves an obsolete Xcode 15 copy on this Mac, which crashes before showing a window.

Keep normal local signing enabled: the simulator needs the app's shared Keychain entitlements
for session persistence and the share extension.

## Verification

- StashKit: **894 tests passed**, zero failures, including eight masonry cases and five fluid cases.
- Simulator app + embedded share extension build: passed, including the final landscape-axis correction.
- **Eight targeted UI checks passed** across two runs:
  - pool rendering in both injected motion directions;
  - a pixel-identical still under Reduce Motion and usable sign-in fields;
  - Ask thinking/writing/completion, interruption, and pre-answer failure cleanup;
  - Ask with Reduce Motion;
  - long-thread follow/hold scrolling during streaming;
  - main screen/search/keyboard navigation and large-text captures;
  - fixed chronological masonry, independent gaps, and card-to-detail navigation;
  - one-column masonry at accessibility text size.
- Fresh sign-in, masonry, Ask and large-text screenshots were visually inspected. The motion
  preview is a real simulator recording with DEBUG-only injected forces.
- The earlier redesign pass also verified Bold Text, font scaling, 44 pt targets and share compose.
- `git diff --check`: passed.

### Review artifacts

- [Screenshot gallery](ios-design-v2/index.html) — twelve simulator captures and a motion clip.
- [Motion preview](ios-design-v2/ascii-motion.mp4) — 12 seconds of simulated left/right movement.
- Motion/Ask UI results: `/private/tmp/stash-ios-motion-core.xcresult` (five tests).
- Masonry/screen UI results: `/private/tmp/stash-ios-motion-layout.xcresult` (three tests).
- Unit log: `/private/tmp/stash-ios-motion-unit.log`.
- Original review build log: `/private/tmp/stash-ios-motion-final-build.log`.
- Main-checkout integration build log: `/private/tmp/stash-ios-main-ui-build.log`.

The approved UI is implemented in the main app and ready for simulator use. Physical sensor feel, device performance and large-library
memory profiling still need a device pass. The full UI regression suite and the web’s per-card
pixel animation are outside this verification pass.

No web deployment, TestFlight upload or App Store submission was performed.
