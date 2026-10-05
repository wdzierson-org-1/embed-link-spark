# Stash for iOS

`Stash.xcodeproj` is generated (by [XcodeGen](https://github.com/yonaskolb/XcodeGen))
from `project.yml` and is gitignored — it is never committed and never
survives a `git pull`/branch switch as-is.

**Run `cd ios && xcodegen generate` after every pull** (and after any
`project.yml` edit) before opening/building in Xcode. Skipping this is the
#1 cause of "Cannot find 'StashType' in scope" (or any other in-repo type)
errors in Xcode: you're looking at a stale project referencing source files
that have since moved/renamed/been added, or a project generated against an
older `project.yml`.

Unit tests: `cd StashKit && swift test`. Release pipeline: see
`../docs/RELEASING.md`.

## UI tests (`StashUITests`)

Build once into a derived-data folder (from `ios/`, after `xcodegen generate`), then run suites
against that build:

```sh
xcodebuild build-for-testing -project Stash.xcodeproj -scheme Stash \
  -destination "platform=iOS Simulator,id=<udid>" -derivedDataPath <dd>
xcodebuild test-without-building -project Stash.xcodeproj -scheme Stash \
  -destination "platform=iOS Simulator,id=<udid>" -derivedDataPath <dd> \
  -collect-test-diagnostics never -only-testing:StashUITests/<Class>[/<test>]
```

The suites sign in as the test account and talk to the real backend. Its credentials live in
`ios/.env.test.local` (gitignored: `STASH_TEST_EMAIL`, `STASH_TEST_PASSWORD`); hand them to the
runner as `TEST_RUNNER_STASH_TEST_EMAIL` / `TEST_RUNNER_STASH_TEST_PASSWORD`, and never print
them. Rows a test seeds carry a `UITEST-P16-` marker and are deleted in its teardown; the
`UITEST-FIXTURE` rows are permanent — never modify them.

### Reading a run

- Most skips are by design: the host-orchestrated share test, the env-gated probes (VoiceOver, Large
  Content Viewer), an OS-specific scroll check, missing credentials. Each says what to set, or why.
- **A skip whose reason starts `UNVERIFIED, RE-RUN THIS TEST` is not one of them.** Xcode's accessibility
  audit never completed on a screen — it timed out, and again on its retry, while the app kept
  answering — so that screen is unaudited, though everything else in the test passed. Re-run that test.
  Repeated timeouts were also reproduced on iOS 17.0's Ask composer at xxxLarge during the
  October 4 completion pass. The Ask matrix reports this as a failed test; it is still unaudited,
  not an accepted accessibility finding. See `../docs/ios-plan-16-completion.md` for the exact
  disposition. Any other audit error fails the test.

### Simulator state a run can leave behind

- **Bold Text and the text size** (`simctl ui <udid> content_size`) are simulator-global and
  outlive a killed run. The `GLOBAL STATE` note in `StashUITests/A11yScreenshotSupport.swift` says
  how each is restored.
- **A hardware-keyboard event hides the on-screen keyboard from the simulator's next boot.**
  `XCUIElement.typeKey` — the ⌘. test `A11yFoundationUITests.testCommandPeriodOnAHardwareKeyboardIsTheKeyboardCancel`
  (and ⌘A, in `testEditSmoke`'s title clear and `A11yDetailLibraryUITests.openDetail`, which should
  do the same; only ⌘. was measured) — makes iOS write `AutomaticMinimizationEnabled` (and, on
  iOS 17, `KeyboardHardwareKeyboardsSeen`) into the simulator's `com.apple.keyboard.preferences`.
  The keyboard still shows for the rest of that boot, so nothing fails at once. After the next
  shutdown/boot it is minimized — in the tree, but parked below the screen — in every app, and the
  tests that assert its frame fail with "Expected the keyboard on screen" (`AskUITests`,
  `testALongThreadKeepsItsEndWhenTheKeyboardComesUp`, …). Restarting the simulator does **not**
  undo it (it is where the damage shows, which is why the failures look intermittent). Measured on
  iOS 17.5 and 26.5: ⌘. then a keyboard test, same boot, passes; after a reboot, fails (keyboard
  top at 897 on an 852 pt screen, 952 on 874); with the key deleted, passes again.

  Restore, with the simulator booted (the next app launch picks it up; `simctl erase <udid>` also
  works, but wipes everything). It exits 1, harmlessly, when the key isn't there:

  ```sh
  xcrun simctl spawn <udid> defaults delete com.apple.keyboard.preferences AutomaticMinimizationEnabled || true
  ```

  In a full-suite run XCTest goes class by class in alphabetical order, so the ⌘. test
  (`A11yFoundationUITests`) runs before `AskUITests`, `ComposerUITests` and `StashUITests`. Keep it
  out of the main run (`-skip-testing:StashUITests/A11yFoundationUITests/testCommandPeriodOnAHardwareKeyboardIsTheKeyboardCancel`),
  run it on its own last, and run the restore above after it — and before the first keyboard suite
  on a simulator you did not set up yourself. Never toggle the Simulator app's own *Connect Hardware
  Keyboard* (it is shared by every session on the Mac), and never touch someone else's simulator.
