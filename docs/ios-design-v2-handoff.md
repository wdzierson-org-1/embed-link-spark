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
The library uses two columns at normal text sizes and one at accessibility sizes.
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

- StashKit: **881 tests passed**, zero failures.
- Simulator app + embedded share extension build: passed.
- Five targeted UI checks passed across the acceptance runs: 44 pt tap targets,
  Bold Text, font scaling, screen/search/keyboard navigation, and share compose.
- The final acceptance run executed four tests with zero failures. It includes real
  simulator captures of Add, library, detail, Ask, keyboard, sign-in, settings,
  accessibility-size layouts, and the share extension.
- The final screenshot set was visually inspected, including the Ask status bar,
  accessibility reflow and the share extension. The latter was opened and cancelled;
  the review tests do not save content or send chat messages.
- `git diff --check`: passed.

### Review artifacts

- [Screenshot gallery](ios-design-v2/index.html) — eleven actual simulator captures.
- Final UI results: `/private/tmp/stash-ios-design-v2-final.xcresult`.
- Tap-target UI results: `/private/tmp/stash-ios-design-v2-review.xcresult`.
- Unit log: `/private/tmp/stash-ios-design-v2-unit.log`.
- Final app/test build log: `/private/tmp/stash-ios-design-v2-handoff-build.log`.

This is a simulator review candidate. The full UI regression suite, physical-device
checks and the web's per-card pixel animation are outside this verification pass.

No web deployment, TestFlight upload or App Store submission was performed.
