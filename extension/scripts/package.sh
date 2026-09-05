#!/bin/bash
# Build the Chrome Web Store submission zip for the Stash it extension.
#
# Zips the manifest + runtime sources + icons — excludes test/, package.json,
# node_modules/, store/, and this scripts/ directory (none of that ships to
# users or belongs in the reviewed package). Output: stash-it-<version>.zip
# in the extension/ directory, named after manifest.json's current version.
#
# Usage: cd extension && ./scripts/package.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."   # extension/

VERSION=$(node -e "console.log(require('./manifest.json').version)")
if [ -z "$VERSION" ]; then
  echo "error: could not read version from manifest.json" >&2
  exit 1
fi

OUT="stash-it-${VERSION}.zip"
rm -f "$OUT"

# zip -x excludes are matched against paths as they're added; -r recurses.
zip -r -X "$OUT" . \
  -x "test/*" \
  -x "package.json" \
  -x "node_modules/*" \
  -x "store/*" \
  -x "scripts/*" \
  -x ".DS_Store" -x "*/.DS_Store" \
  -x "*.zip"

echo "Built $OUT ($(du -h "$OUT" | cut -f1))"
echo
echo "Contents:"
unzip -l "$OUT"
