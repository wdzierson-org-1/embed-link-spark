#!/usr/bin/env bash
# Scripted release pipeline: archive -> export -> upload.
#
# Key discovery contract (Task 4/5 depend on this exactly):
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
# read from config.env — the file is sourced, not printed.
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

cmd_generate() {
  xcodegen generate
}

cmd_archive() {
  require_key
  xcodebuild archive \
    -project Stash.xcodeproj \
    -scheme Stash \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$KEY_PATH" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"
}

cmd_export() {
  require_key
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist scripts/ExportOptions-export.plist \
    -exportPath "$EXPORT_PATH" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$KEY_PATH" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"
}

cmd_upload() {
  require_key
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist scripts/ExportOptions-upload.plist \
    -exportPath "$EXPORT_PATH" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$KEY_PATH" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"
}

cmd_all() {
  cmd_generate
  cmd_archive
  cmd_export
}

usage() {
  echo "Usage: $0 {generate|archive|export|upload|all}" >&2
  exit 1
}

if [[ $# -ne 1 ]]; then
  usage
fi

case "$1" in
  generate) cmd_generate ;;
  archive) cmd_archive ;;
  export) cmd_export ;;
  upload) cmd_upload ;;
  all) cmd_all ;;
  *) usage ;;
esac
