# iOS design v2 — simulator handoff

## Integrated app

The October 10 update is implemented on `codex/ios-design-v2`, building on local main
`575deb2e`. The primary checkout is `/Users/will/Appdev/embed-link-spark`.
The simulator gallery contains real native captures using the review account.

## October 10 — compact detail follow-up

- Two-line titles expand on tap into a full editor with square Save / Cancel. Unsaved drafts
  stay local; committed titles follow the existing durable pipeline.
- Descriptions follow the main visual. The type badge and source Copy/Open buttons are removed.
- Video links show Summary / Transcript only, with an honest empty state for unverified source text.
- Share item is a compact paper toast with square X and one full-width Copy link action.
  Existing tokens are reused and feed privacy stays unchanged.

### Verification of this follow-up

- **20 focused StashKit tests pass**, covering video tabs, transcript evidence, edited addresses,
  canonical video links and conservative provider classification.
- **Two native acceptance flows pass** across separate runs. Title coverage includes two-line
  truncation, full draft focus, no autosave before Save, Cancel, durable Save/relaunch, preserved
  notes/source text/privacy, media-first order, and reachable AX3 controls with the keyboard open.
  Item sharing covers Copy feedback, anonymous access, token reuse after closing/reopening,
  and unchanged feed privacy. Disposable review-account fixtures are cleaned up by exact ID.
- Real native screenshots were reviewed and added to the gallery, including the AX3 title editor.
- The verified app is installed and running on **Stash Design v2**; a simulator capture confirms
  the owner's signed-in library remains intact. The Mac locked before the final window-foreground
  check, so Device Hub could not be raised; select Stash Design v2 after unlocking if needed.

Evidence:

- Unit log: `/private/tmp/stash-detail-video-classification-green.log`
- Native build and compiled legacy test migrations: `/private/tmp/stash-detail-refinement-final-build2.log`
- Title acceptance: `/private/tmp/stash-detail-refinement-v4-ui.xcresult`
- Share acceptance: `/private/tmp/stash-detail-refinement-v2-ui.xcresult` (share flow passes;
  the earlier title scroll-helper failure is resolved in the title run above)

Legacy title tests have been migrated to explicit Save and draft isolation. Autosave race
coverage uses the description field, which retains that behavior. These migrations are compiled;
the complete legacy UI suite has not been rerun. The earlier 958-test full StashKit result and
playback acceptance below belong to the preceding pass.

## October 10 — revised toast and detail controls (earlier pass)

- Navigation remains **View, Ask, Add, Settings**.
- Share toast: bordered media/link preview and note input, a visible retro **Share to feed**
  toggle, square **Save** and location buttons on one row with a gap. Location reverses to
  white on black when on; its status appears above Save. No More options or Dictate a note.
- Location consent remains per-account across Add and the extension. Missing permissions or
  GPS never block Save. Preview work remains optional with its existing 500 ms deadline;
  durable capture and normal enrichment continue independently.
- Detail videos play inline with a full-screen toggle. Native uploads use AVPlayer; supported
  links use isolated provider players. Playback starts only after a tap. Full screen retains
  the same player; leaving detail or backgrounding pauses it. Provider restrictions can still
  require **Open original**.
- Header **Share** creates/manages an unlisted item link. Copy, native sharing and revocation
  use the existing backend contract and never toggle public feed visibility.
- Video source tabs follow the web's transcript evidence flag. Summary sits beside Transcript;
  Original Content remains until the server identifies a transcript. Generic scraped text is
  never labeled as a transcript.
- Existing source addresses have Copy / Edit / Open controls, with explicit Save / Cancel.
  Address edits use the durable queue, clear metadata from the old address, and preserve
  captured source text, notes, summary, media and location. No backend migration is needed.

Web reference: `app-redesign-v2` at `4315aa49`. The earlier ASCII sign-in pool,
masonry library and rotating thinking cursor remain in place.

### Verification of the earlier pass

The prior full StashKit suite passed **958 tests**. The real Safari share flow passes: feed on/off, square Save beside the pin, location status,
note entry, confirmation within 500 ms and exactly one private server item. The AX3 check
passes for first-tap note focus, pinned Save above the keyboard, touch targets and audit.
Address-edit acceptance passes for invalid input, cancel, save, metadata cleanup, preserved
notes/source text and relaunch. The test suite uses a dedicated QA simulator and disposable
review-account items, leaving the owner's account unchanged. Native AVPlayer and YouTube
playback both pass real play-clock and full-screen continuity checks. Item sharing passes
creation, copy, native sharing, anonymous access, revocation and feed-privacy checks.

The verified build is installed and open on **Stash Design v2** with its existing signed-in
library preserved. The gallery uses review-account fixtures, not the owner's private items.

- Unit log: `/private/tmp/stash-detail-share-v3-unit.log`
- Native build: `/private/tmp/stash-detail-share-v3-build7.log`
- Toast: `/private/tmp/stash-detail-share-v3-ui.xcresult` (toast test passes; initial detail test selectors corrected afterward)
- Larger text: `/private/tmp/stash-share-v3-large-ui.xcresult`
- Address editing: `/private/tmp/stash-detail-share-v4-ui.xcresult` (address test passes)
- Item-link sharing: `/private/tmp/stash-detail-share-v5-ui.xcresult` (share test passes)
- Embedded playback: `/private/tmp/stash-detail-share-v6-ui.xcresult` (YouTube test passes)
- Native playback: `/private/tmp/stash-detail-share-v7-ui.xcresult`

Physical-device GPS and gyroscope feel still require an iPhone check.

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

## Original redesign verification

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

- [Screenshot gallery](ios-design-v2/index.html) — native simulator captures and a motion clip.
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
