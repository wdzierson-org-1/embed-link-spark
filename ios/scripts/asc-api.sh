#!/usr/bin/env bash
# Minimal App Store Connect REST API helper. Used for everything xcodebuild
# doesn't cover: build-processing polls, beta groups/testers, users, apps,
# metadata PATCHes, and (plan-14 Task 4b) the App Store screenshot upload
# flow. (xcodebuild itself uses the logged-in Xcode SESSION, not this key —
# see docs/RELEASING.md "The auth split" for why the two are not
# interchangeable.)
#
# Usage: ./asc-api.sh METHOD PATH [extra curl args...]
#   METHOD           GET, POST, PATCH, DELETE, ...
#   PATH             an ASC API path, e.g. "/v1/apps?limit=5" or "/v1/betaGroups"
#   extra curl args  optional, passed through to curl before the URL, e.g.
#                    -H "Content-Type: application/json" -d '{"data":{...}}'
#
# Usage (screenshot upload, plan-14 Task 4b):
#   ./asc-api.sh upload-screenshot <appScreenshotSetId> <path/to/screenshot.png>
#   Implements Apple's reserve -> PUT chunks -> commit -> poll flow in one
#   call: POST /v1/appScreenshots (reserve, returns uploadOperations), PUT
#   each operation's byte range with its own returned headers (never our own
#   Authorization header — the upload URLs are pre-signed), PATCH
#   /v1/appScreenshots/<id> with `uploaded: true` + the md5 `sourceFileChecksum`
#   to commit, then poll GET /v1/appScreenshots/<id> until
#   `attributes.assetDeliveryState.state` reaches COMPLETE (or FAILED/ERROR,
#   reported and exited non-zero). Requires `jq` (already on this machine).
#
# Prints the response body on stdout; prints "HTTP <code>" on stderr.
# Never echoes the API key, issuer ID, key ID, or JWT.
#
# Key discovery contract (same as release.sh):
#   ios/.asc/config.env defines ASC_KEY_ID and ASC_ISSUER_ID.
#   The .p8 sits at ios/.asc/AuthKey_${ASC_KEY_ID}.p8.
# See ios/.asc/README.md for how to obtain and place the key.
#
# Example: ./asc-api.sh GET "/v1/builds?filter[app]=6806459949&sort=-uploadedDate"
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

ASC_DIR="$IOS_DIR/.asc"
ASC_README="ios/.asc/README.md"
ASC_CONFIG="$ASC_DIR/config.env"

fail_no_key() {
  echo "error: no App Store Connect API key found. Drop your key per $ASC_README, then retry." >&2
  exit 1
}

usage() {
  echo "Usage: $0 METHOD PATH [extra curl args...]" >&2
  echo '  e.g. ./asc-api.sh GET "/v1/apps?limit=5"' >&2
  echo '       ./asc-api.sh POST /v1/betaGroups -H "Content-Type: application/json" -d "{...}"' >&2
  echo "       $0 upload-screenshot <appScreenshotSetId> <path/to/screenshot.png>" >&2
  exit 1
}

if [[ $# -lt 2 ]]; then
  usage
fi

# Sources ios/.asc/config.env and resolves the .p8 path. Never echoes
# anything read from config.env — the file is sourced, not printed.
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

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# Builds a short-lived (10 min) ES256 JWT per Apple's ASC API auth spec. A
# function (not inline top-level code) so the screenshot-upload flow below —
# which can run long enough across several PUTs + polls to want a fresh
# token per call — can call this repeatedly instead of relying on one token
# for the whole invocation.
asc_jwt() {
  local now exp header payload signature
  now=$(date +%s)
  exp=$((now + 590))
  header=$(printf '{"alg":"ES256","kid":"%s","typ":"JWT"}' "$ASC_KEY_ID" | b64url)
  payload=$(printf '{"iss":"%s","iat":%d,"exp":%d,"aud":"appstoreconnect-v1"}' "$ASC_ISSUER_ID" "$now" "$exp" | b64url)
  signature=$(printf '%s.%s' "$header" "$payload" \
    | openssl dgst -sha256 -sign "$KEY_PATH" -binary \
    | openssl asn1parse -inform DER \
    | awk -F: '/INTEGER/{print $4}' \
    | while read -r h; do printf '%064s' "$h" | tr ' ' '0'; done \
    | xxd -r -p \
    | b64url)
  printf '%s.%s.%s' "$header" "$payload" "$signature"
}

# Generic authenticated call. Sets globals $ASC_LAST_BODY and $ASC_LAST_HTTP
# rather than returning via a `$(...)` command substitution — a substitution
# runs the function in a subshell, which would silently drop any global
# variable it sets (confirmed live: an earlier version of this function did
# exactly that and every caller crashed on "ASC_LAST_HTTP: unbound
# variable" under `set -u`). Call it as a plain statement, then read the
# globals; callers below all follow this shape.
# curl -w appends "\n<http_code>" after the body so the two can be split
# reliably regardless of what the body itself contains. -g (--globoff) is
# required: ASC filter params look like "filter[app]=..." and curl's URL
# globbing otherwise reads "[app]" as a range expression and fails the
# whole request with "URL malformed" (exit 3) before it ever hits the network.
asc_call() {
  local method="$1" path="$2"
  shift 2
  local response
  response=$(curl -sg -w $'\n%{http_code}' -X "$method" \
    -H "Authorization: Bearer $(asc_jwt)" \
    "$@" \
    "https://api.appstoreconnect.apple.com${path}")
  ASC_LAST_HTTP=$(printf '%s' "$response" | tail -n1)
  ASC_LAST_BODY=$(printf '%s' "$response" | sed '$d')
}

# --- Screenshot upload subcommand (plan-14 Task 4b) ---------------------
upload_screenshot() {
  local set_id="$1" png_path="$2"
  if [[ ! -f "$png_path" ]]; then
    echo "error: screenshot file not found: $png_path" >&2
    exit 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "error: upload-screenshot requires jq (not found on PATH)." >&2
    exit 1
  fi

  local file_name file_size
  file_name="$(basename "$png_path")"
  file_size="$(stat -f%z "$png_path" 2>/dev/null || stat -c%s "$png_path")"

  echo "-- reserving appScreenshot for $file_name ($file_size bytes) in set $set_id" >&2
  local reserve_body reserve_json screenshot_id upload_ops_json
  reserve_body=$(jq -n --arg name "$file_name" --argjson size "$file_size" --arg setId "$set_id" '
    {data: {type: "appScreenshots", attributes: {fileName: $name, fileSize: $size},
            relationships: {appScreenshotSet: {data: {type: "appScreenshotSets", id: $setId}}}}}')
  asc_call POST "/v1/appScreenshots" -H "Content-Type: application/json" -d "$reserve_body"
  reserve_json="$ASC_LAST_BODY"
  if [[ "$ASC_LAST_HTTP" -ge 300 ]]; then
    echo "error: reserve failed (HTTP $ASC_LAST_HTTP): $reserve_json" >&2
    exit 1
  fi
  screenshot_id=$(jq -r '.data.id' <<<"$reserve_json")
  upload_ops_json=$(jq -c '.data.attributes.uploadOperations' <<<"$reserve_json")
  if [[ -z "$screenshot_id" || "$screenshot_id" == "null" ]]; then
    echo "error: reserve response had no screenshot id: $reserve_json" >&2
    exit 1
  fi
  echo "-- reserved appScreenshot id $screenshot_id, $(jq 'length' <<<"$upload_ops_json") upload operation(s)" >&2

  local n op_count
  op_count=$(jq 'length' <<<"$upload_ops_json")
  for ((n = 0; n < op_count; n++)); do
    local op method url offset length header_args tmp_chunk
    op=$(jq -c ".[$n]" <<<"$upload_ops_json")
    method=$(jq -r '.method' <<<"$op")
    url=$(jq -r '.url' <<<"$op")
    offset=$(jq -r '.offset' <<<"$op")
    length=$(jq -r '.length' <<<"$op")

    tmp_chunk="$(mktemp)"
    # dd extracts exactly this operation's byte range from the source PNG —
    # Apple's multi-part upload contract splits large files across several
    # PUTs, each addressed by its own offset/length pair.
    dd if="$png_path" of="$tmp_chunk" bs=1 skip="$offset" count="$length" status=none

    header_args=()
    local h_count
    h_count=$(jq '.requestHeaders | length' <<<"$op")
    for ((h = 0; h < h_count; h++)); do
      local hname hvalue
      hname=$(jq -r ".requestHeaders[$h].name" <<<"$op")
      hvalue=$(jq -r ".requestHeaders[$h].value" <<<"$op")
      header_args+=(-H "$hname: $hvalue")
    done

    echo "-- PUT chunk $((n + 1))/$op_count (offset $offset, length $length)" >&2
    # Deliberately NO Authorization/JWT header here — uploadOperations URLs
    # are pre-signed by Apple for this exact byte range; the only headers
    # that belong on this request are the ones Apple returned above.
    local put_http
    put_http=$(curl -sg -o /dev/null -w '%{http_code}' -X "${method:-PUT}" "${header_args[@]}" --data-binary "@$tmp_chunk" "$url")
    rm -f "$tmp_chunk"
    if [[ "$put_http" -ge 300 ]]; then
      echo "error: PUT chunk $((n + 1))/$op_count failed (HTTP $put_http)" >&2
      exit 1
    fi
  done

  local checksum commit_body commit_json
  checksum=$(md5 -q "$png_path" 2>/dev/null || md5sum "$png_path" | awk '{print $1}')
  echo "-- committing appScreenshot $screenshot_id (md5 $checksum)" >&2
  commit_body=$(jq -n --arg id "$screenshot_id" --arg sum "$checksum" '
    {data: {type: "appScreenshots", id: $id, attributes: {uploaded: true, sourceFileChecksum: $sum}}}')
  asc_call PATCH "/v1/appScreenshots/$screenshot_id" -H "Content-Type: application/json" -d "$commit_body"
  commit_json="$ASC_LAST_BODY"
  if [[ "$ASC_LAST_HTTP" -ge 300 ]]; then
    echo "error: commit failed (HTTP $ASC_LAST_HTTP): $commit_json" >&2
    exit 1
  fi

  echo "-- polling assetDeliveryState for $screenshot_id" >&2
  local deadline state poll_json
  deadline=$(($(date +%s) + 120))
  state="UNKNOWN"
  while [[ $(date +%s) -lt $deadline ]]; do
    asc_call GET "/v1/appScreenshots/$screenshot_id"
    poll_json="$ASC_LAST_BODY"
    state=$(jq -r '.data.attributes.assetDeliveryState.state // "UNKNOWN"' <<<"$poll_json")
    echo "   state=$state" >&2
    if [[ "$state" == "COMPLETE" || "$state" == "FAILED" || "$state" == "ERROR" ]]; then
      break
    fi
    sleep 3
  done

  echo "{\"id\":\"$screenshot_id\",\"fileName\":\"$file_name\",\"state\":\"$state\"}"
  if [[ "$state" != "COMPLETE" ]]; then
    echo "error: appScreenshot $screenshot_id did not reach COMPLETE (final state: $state)" >&2
    exit 1
  fi
}

if [[ "$1" == "upload-screenshot" ]]; then
  if [[ $# -ne 3 ]]; then
    usage
  fi
  upload_screenshot "$2" "$3"
  exit 0
fi

METHOD="$1"
API_PATH="$2"
shift 2

asc_call "$METHOD" "$API_PATH" "$@"
printf '%s\n' "$ASC_LAST_BODY"
echo "HTTP $ASC_LAST_HTTP" >&2
