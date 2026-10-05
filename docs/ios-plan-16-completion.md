# iOS plan 16 — completion and release handoff

Updated October 4, 2026. This is the current status source for the recovered
`worktree-ios-plan-16` work. The original plan and `.superpowers` task reports
retain their historical investigations; their unfinished wrap lists do not
start a new review cycle.

## Scope and disposition

The user approved a bounded stabilization pass: preserve the interrupted work,
resolve or document the remaining failures, run a fixed acceptance set, and
commit and integrate locally. TestFlight publication is a separate step.

- Preserved the seven interrupted Ask files in commit `a459788e`. The rendered
  conversation tail keeps complete exchanges, checks that scroll holds work,
  and handles long system scrolls without animating across unbuilt history.
- Fixed location delivery bookkeeping in commit `aa19bac`. Location changes
  still merge into the server's latest attributes inside the item's serialized
  write. Successful writes now enter the delivery record before the next write.
  An older Brooklyn delivery cannot hide a failed revert after Queens was saved.
  Failed writes remain queued. Two regressions cover delivery ordering and the
  reported false-saved sequence; existing attribute-preservation tests use the
  real application entry point.
- Corrected the live Ask smoke test in commit `fd4d298`. Its failure recording showed a complete
  cited answer, while its query selected old response 19 instead of response 27.
  The test now starts an empty conversation without deleting history and chooses
  a new assistant response from one snapshot using assistant-only identifiers.
  A selector regression covers old history, user messages and traversal order.
- Independently reviewed the recovered seven-file diff and the four-file final
  fix diff. Neither review found a remaining must-fix issue in those changes.
  This was a completion review, not another redesign or app-wide audit.

## Fresh acceptance results

| Check | Result |
| --- | --- |
| Full StashKit suite | 877 tests, zero failures, no skips |
| Location regression before fix | Four assertions fail, including the false-saved state |
| Web regression suite | 526 tests in 66 files, zero failures, Node 22.23.3 |
| Extension regression suite | 15 tests, zero failures |
| Debug app, extension and UI-test build | Pass |
| Unsigned physical-device Release build | Pass; signing and upload not exercised |
| Release app and extension binary scan | Test hooks and scripted fixtures absent; positive symbol controls present |
| Selected iOS 26.5 UI acceptance | 8 tests, zero failures, no skips; includes live Ask and the text-size accessibility matrix |
| iOS 17.0 Ask text-size matrix | Fails only because Xcode's audit twice times out on `ask-composing xxxL`; explicitly unverified |
| Source identity | All compiled source and resource files match the final build export; package snapshot also matched |

The iOS 26.5 set contains the live Ask smoke, assistant selector regression,
Cancel preserving the draft, opening an earlier conversation, far jumps, tail
shedding with working holds, streaming status-bar behavior, and the text-size
accessibility matrix. Existing October 3 logs also cover broader Ask suites on
17.5, 18.5 and 26.5; those historical passes are not counted as fresh full-suite
verification.

The iOS 17.0 audit timeout reproduced in a dedicated simulator with unchanged
application/test code. Subsequent interactions completed. The xxxLarge and AX3
composer screenshots were inspected: text wraps, the composer remains above the
keyboard, and Cancel is visible. Visual inspection does not replace the missing
automated audit. The failed assertion has not been weakened or converted into a
passing test.

Builds have no Swift source warnings. Xcode prints its informational warning that
App Intents metadata extraction is skipped because these targets do not link
AppIntents.framework.

## Explicitly deferred issues

These do not block local integration; they remain visible for release decisions
and follow-up work. No claim of complete accessibility certification is made.

1. **iOS 17.0–17.3 streaming/assistive scrolling.** Animated keyboard or assistive
   scrolling can be pulled back while an answer streams. It predates the recovered
   diff and is explicitly marked as an expected failure on these versions. Do not
   silently raise the deployment target or describe this behavior as fixed.
2. **The iOS 17.0 audit timeout above.** Recheck on a physical device or a changed
   Xcode/runtime environment; repeated identical simulator runs add no evidence.
3. **Previously parked citation-sheet baseline case.** If another refresh delivers
   a queued edit that the citation sheet never adopts, a later revert to the
   sheet's old value may not be sent. The server's value appears on reopen and can
   be edited again. The new location-delivery fix does not claim to close this
   separate baseline/adoption issue. Other pre-existing cross-device sharing
   residuals remain described in `ui-changes.md`.
4. **Physical-device accessibility checks.** VoiceOver focus order, hardware
   keyboard/Voice Control behavior and animation feel still need device checks;
   XCUITest's simulated interactions are not a replacement.

## Release work remaining

- Regenerate the Xcode project after changing checkout: `cd ios && xcodegen generate`.
- Perform the physical-device checks and decide the documented older-iOS limits.
- Archive/sign build 10, refresh App Store screenshots, upload to TestFlight and
  confirm its processing/group availability. No upload or App Store submission
  was performed during this stabilization pass.
- Existing unrelated configuration, agent tooling and draft documents in the
  main checkout are preserved. They are not part of the iOS change set.

## Reproducing checks without reopening the investigation

- Run `swift test --package-path ios/StashKit --scratch-path /tmp/stashkit-check`
  with macOS service access. In the restricted sandbox the Keychain and type
  database checks fail; the same source passed all 877 tests with service access.
- Use a supported Node runtime (22.12+ on the Node 22 line). This shell selected
  Node 19.8.1 inside the repository, which cannot load jsdom's dependencies. The
  accepted web run used the installed Node 22.23.3 executable with
  `node node_modules/vitest/vitest.mjs run --maxWorkers=2`.
- Build UI tests once with `xcodebuild build-for-testing`, then use
  `test-without-building -xctestrun <file>` for the named acceptance tests. Follow
  `ios/README.md` for test credentials and keyboard-state restoration. Use one
  owned simulator at a time and shut it down when finished.
- Logs, `.xcresult` bundles, exact commands and source hashes from this pass are
  under `/tmp/stash-ios-completion/`; these are local evidence, not repository
  dependencies. The completion report keeps the durable result summary.
- Repeat a check only after a relevant change or a specific unresolved result.
  Unrelated minor findings become separate follow-up work.
