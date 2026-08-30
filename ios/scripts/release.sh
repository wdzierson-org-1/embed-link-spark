#!/usr/bin/env bash
# Scripted release pipeline: archive -> export -> upload.
#
# Auth modes for xcodebuild (see docs/RELEASING.md "The auth split" for the
# full story — this is Task 4/5 ground truth, not a guess):
#   session (DEFAULT) - xcodebuild signs using the Xcode account logged into
#     this Mac (Xcode > Settings > Accounts). This is the PROVEN path for
#     archive/export/upload on this setup.
#   key - passes -authenticationKeyPath/-authenticationKeyID/
#     -authenticationKeyIssuerID, sourced from ios/.asc/config.env +
#     ios/.asc/AuthKey_<KEYID>.p8. The API-key path currently FAILS for
#     xcodebuild ("Cloud signing permission error") on this account/team —
#     it's kept here as an explicit opt-in for if Apple ever fixes that, and
#     because the same key IS proven working for ASC REST calls (processing
#     polls, beta groups — see docs/RELEASING.md).
#
# Select a mode with --session-auth / --key-auth, or STASH_RELEASE_AUTH=session|key.
# Default (nothing specified): session.
#
# Key discovery contract (only consulted in key mode):
#   ios/.asc/config.env defines ASC_KEY_ID and ASC_ISSUER_ID.
#   The .p8 sits at ios/.asc/AuthKey_${ASC_KEY_ID}.p8.
# See ios/.asc/README.md for how to obtain and place the key.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$IOS_DIR"

ASC_DIR="$IOS_DIR/.asc"
ASC_README="ios/.asc/README.md"
ASC_CONFIG="$ASC_DIR/config.env"

ARCHIVE_PATH="build/Stash.xcarchive"
EXPORT_PATH="build/export"

fail_no_key() {
  echo "error: no App Store Connect API key found. Drop your key per $ASC_README, then retry." >&2
  exit 1
}

# Sources ios/.asc/config.env and resolves the .p8 path. Never echoes anything
# read from config.env — the file is sourced, not printed. Only called for
# AUTH_MODE=key (explicitly requested) — session mode never touches this, so
# a missing key never blocks the default (proven) release path.
require_key() {
  if [[ ! -f "$ASC_CONFIG" ]]; then
    fail_no_key
  fi

  # shellcheck disable=SC1090
  source "$ASC_CONFIG"

  if [[ -z "${ASC_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" ]]; then
    echo "error: $ASC_CONFIG is missing ASC_KEY_ID or ASC_ISSUER_ID. See $ASC_README." >&2
    exit 1
  fi

  KEY_PATH="$ASC_DIR/AuthKey_${ASC_KEY_ID}.p8"
  if [[ ! -f "$KEY_PATH" ]]; then
    fail_no_key
  fi
}

# AUTH_MODE: "session" (default) or "key". A flag (--session-auth/--key-auth)
# wins over STASH_RELEASE_AUTH, which wins over the session default.
AUTH_MODE="${STASH_RELEASE_AUTH:-session}"
case "$AUTH_MODE" in
  session|key) ;;
  *)
    echo "error: STASH_RELEASE_AUTH must be 'session' or 'key' (got '$AUTH_MODE')." >&2
    exit 1
    ;;
esac

# Populates the global AUTH_FLAGS array for the current AUTH_MODE: empty for
# session auth (xcodebuild then signs with the logged-in Xcode account), or
# the three -authenticationKey* flags for key auth. Bash 3.2 (macOS default)
# treats "${AUTH_FLAGS[@]}" on an empty array as an unbound-variable error
# under `set -u`, so every call site expands it as
# "${AUTH_FLAGS[@]+"${AUTH_FLAGS[@]}"}" instead.
auth_flags() {
  AUTH_FLAGS=()
  if [[ "$AUTH_MODE" == "key" ]]; then
    require_key
    AUTH_FLAGS=(-authenticationKeyPath "$KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
  fi
}

cmd_generate() {
  xcodegen generate
}

cmd_archive() {
  auth_flags
  xcodebuild archive \
    -project Stash.xcodeproj \
    -scheme Stash \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    "${AUTH_FLAGS[@]+"${AUTH_FLAGS[@]}"}"
}

cmd_export() {
  auth_flags
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist scripts/ExportOptions-export.plist \
    -exportPath "$EXPORT_PATH" \
    -allowProvisioningUpdates \
    "${AUTH_FLAGS[@]+"${AUTH_FLAGS[@]}"}"
}

cmd_upload() {
  auth_flags
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist scripts/ExportOptions-upload.plist \
    -exportPath "$EXPORT_PATH" \
    -allowProvisioningUpdates \
    "${AUTH_FLAGS[@]+"${AUTH_FLAGS[@]}"}"
}

cmd_all() {
  cmd_generate
  cmd_archive
  cmd_export
}

usage() {
  echo "Usage: $0 {generate|archive|export|upload|all} [--session-auth|--key-auth]" >&2
  echo "       (or set STASH_RELEASE_AUTH=session|key). Default: session." >&2
  exit 1
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
fi

COMMAND="$1"
if [[ $# -eq 2 ]]; then
  case "$2" in
    --session-auth) AUTH_MODE="session" ;;
    --key-auth) AUTH_MODE="key" ;;
    *) usage ;;
  esac
fi

case "$COMMAND" in
  generate) cmd_generate ;;
  archive) cmd_archive ;;
  export) cmd_export ;;
  upload) cmd_upload ;;
  all) cmd_all ;;
  *) usage ;;
esac
