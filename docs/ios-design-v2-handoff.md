# iOS design v2 — simulator handoff

## Candidate

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
  backed by a native particle/grid fluid simulation. Core Motion tilts the pool and adds a
  directional force for phone movement; the form stays still. Nothing is recorded or uploaded.
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

Core Motion follows Apple’s [start/stop lifecycle](https://developer.apple.com/documentation/coremotion/cmmotionmanager/startdevicemotionupdates()).

## Run it again

```sh
cd /Users/will/Documents/ChatGPT/Stash/worktrees/ios-design-v2/ios
xcodegen generate
xcodebuild build -project Stash.xcodeproj -scheme Stash \
  -destination 'platform=iOS Simulator,id=B6845555-0DE1-40FB-A77F-FF411946AA5F' \
  -derivedDataPath /private/tmp/stash-ios-design-v2-build
xcrun simctl install B6845555-0DE1-40FB-A77F-FF411946AA5F \
  /private/tmp/stash-ios-design-v2-build/Build/Products/Debug-iphonesimulator/Stash.app
xcrun simctl launch B6845555-0DE1-40FB-A77F-FF411946AA5F it.gostash.stash
open -a Simulator --args -CurrentDeviceUDID B6845555-0DE1-40FB-A77F-FF411946AA5F
```

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
- Final app build log: `/private/tmp/stash-ios-motion-final-build.log`.

This is a simulator review candidate. Physical sensor feel, device performance and large-library
memory profiling still need a device pass. The full UI regression suite and the web’s per-card
pixel animation are outside this verification pass.

No web deployment, TestFlight upload or App Store submission was performed.
