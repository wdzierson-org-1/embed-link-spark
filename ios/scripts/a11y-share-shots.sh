#!/usr/bin/env bash
# The share sheet's accessibility screenshot matrix (plan 16): runs
# StashUITests/A11yAppUITests/testShareComposeScreenshot once per text size — L, xxxL, AX3,
# L-bold — on one simulator, from an existing `xcodebuild build-for-testing` of this project.
#
# The share extension is Safari's child process, so no launch argument reaches it. For each size
# this sets the SIMULATOR's text size (`xcrun simctl ui <udid> content_size …`) and runs the test
# alone with TEST_RUNNER_A11Y_SHARE_TOKEN=<size>; the first run also signs in (the extension reads
# the app's stored session). The text size is simulator-global and outlives the run, so an EXIT
# trap puts it back to `large` however this script ends — a failed run, a failed command or
# Ctrl-C included. (A shell killed outright skips even that: the test
# A11yAppUITests/testSimulatorTextSettingsAreTheDefaults reports the leak, and
# `xcrun simctl ui <udid> content_size large` repairs it.) L-bold turns the REAL Bold Text
# setting on through the Settings app; the test's own teardown turns it off again.
#
# Usage: ios/scripts/a11y-share-shots.sh <simulator-udid> <derived-data-path> <results-dir> [size…]
#   <derived-data-path>  the -derivedDataPath the project was built for testing into
#   <results-dir>        receives <size>.xcresult and <size>.log for each size
#   size                 any of L xxxL AX3 L-bold (default: all four, in that order)
# Environment:
#   STASH_TEST_ENV_FILE  the credentials file (default: ios/.env.test.local); its
#                        STASH_TEST_EMAIL / STASH_TEST_PASSWORD reach the test runner as
#                        TEST_RUNNER_*, and are never printed
#   A11Y_SHARE_SIGN_IN=0 skip the first run's sign-in (the app is already signed in)
# Export the shots afterwards with xcrun xcresulttool (`export attachments`); they are named
# a11y-[ios26-]share-<size> and a11y-[ios26-]share-note-<size>.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ $# -lt 3 ]]; then
  echo "usage: $0 <simulator-udid> <derived-data-path> <results-dir> [L|xxxL|AX3|L-bold …]" >&2
  exit 2
fi
UDID=$1
DERIVED=$2
RESULTS=$3
shift 3
if [[ $# -gt 0 ]]; then SIZES=("$@"); else SIZES=(L xxxL AX3 L-bold); fi
for size in "${SIZES[@]}"; do
  case $size in
    L|xxxL|AX3|L-bold) ;;
    *) echo "error: unknown size '$size' (use L, xxxL, AX3 or L-bold)" >&2; exit 2 ;;
  esac
done

ENV_FILE=${STASH_TEST_ENV_FILE:-$IOS_DIR/.env.test.local}
if [[ ! -f "$ENV_FILE" ]]; then
  echo "error: no credentials file at $ENV_FILE (set STASH_TEST_ENV_FILE)" >&2
  exit 1
fi
# shellcheck disable=SC1090
. "$ENV_FILE"
export TEST_RUNNER_STASH_TEST_EMAIL="${STASH_TEST_EMAIL:?is not set in the credentials file}"
export TEST_RUNNER_STASH_TEST_PASSWORD="${STASH_TEST_PASSWORD:?is not set in the credentials file}"

reset_text_size() {
  xcrun simctl ui "$UDID" content_size large || true
  echo "text size reset: $(xcrun simctl ui "$UDID" content_size 2>/dev/null || echo unknown)"
}
trap reset_text_size EXIT
trap 'exit 130' INT TERM HUP

mkdir -p "$RESULTS"
first=1
status=0
for size in "${SIZES[@]}"; do
  case $size in
    L|L-bold) category=large ;;
    xxxL) category=extra-extra-extra-large ;;
    AX3) category=accessibility-extra-large ;;
  esac
  xcrun simctl ui "$UDID" content_size "$category"
  echo "== $size: simulator text size $(xcrun simctl ui "$UDID" content_size)"
  export TEST_RUNNER_A11Y_SHARE_TOKEN="$size"
  if [[ $first == 1 && "${A11Y_SHARE_SIGN_IN:-1}" == 1 ]]; then
    export TEST_RUNNER_A11Y_SHARE_SIGN_IN=1
  else
    unset TEST_RUNNER_A11Y_SHARE_SIGN_IN
  fi
  first=0
  rm -rf "$RESULTS/$size.xcresult"
  if xcodebuild test-without-building \
      -project "$IOS_DIR/Stash.xcodeproj" -scheme Stash \
      -destination "platform=iOS Simulator,id=$UDID" \
      -derivedDataPath "$DERIVED" \
      -collect-test-diagnostics never \
      -resultBundlePath "$RESULTS/$size.xcresult" \
      -only-testing:StashUITests/A11yAppUITests/testShareComposeScreenshot > "$RESULTS/$size.log" 2>&1; then
    echo "== $size: passed"
  else
    echo "== $size: FAILED (see $RESULTS/$size.log)"
    status=1
  fi
  grep -E "Test Case .*(passed|failed|skipped)|error: |A11Y share" "$RESULTS/$size.log" | cut -c1-300 || true
done
exit $status
