#!/usr/bin/env bash
# Minimal App Store Connect REST API helper. Used for everything xcodebuild
# doesn't cover: build-processing polls, beta groups/testers, users, apps.
# (xcodebuild itself uses the logged-in Xcode SESSION, not this key — see
# docs/RELEASING.md "The auth split" for why the two are not interchangeable.)
#
# Usage: ./asc-api.sh METHOD PATH [extra curl args...]
#   METHOD           GET, POST, PATCH, DELETE, ...
#   PATH             an ASC API path, e.g. "/v1/apps?limit=5" or "/v1/betaGroups"
#   extra curl args  optional, passed through to curl before the URL, e.g.
#                    -H "Content-Type: application/json" -d '{"data":{...}}'
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
  exit 1
}

if [[ $# -lt 2 ]]; then
  usage
fi

METHOD="$1"
API_PATH="$2"
shift 2

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

# Builds a short-lived (10 min) ES256 JWT per Apple's ASC API auth spec.
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
JWT="$header.$payload.$signature"

# curl -w appends "\n<http_code>" after the body so the two can be split
# reliably regardless of what the body itself contains. -g (--globoff) is
# required: ASC filter params look like "filter[app]=..." and curl's URL
# globbing otherwise reads "[app]" as a range expression and fails the
# whole request with "URL malformed" (exit 3) before it ever hits the network.
response=$(curl -sg -w $'\n%{http_code}' -X "$METHOD" \
  -H "Authorization: Bearer $JWT" \
  "$@" \
  "https://api.appstoreconnect.apple.com${API_PATH}")

http_code=$(printf '%s' "$response" | tail -n1)
body=$(printf '%s' "$response" | sed '$d')

printf '%s\n' "$body"
echo "HTTP $http_code" >&2
