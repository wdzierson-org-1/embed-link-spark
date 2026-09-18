#!/bin/bash
# Refresh the hosted "grab it here" zip at gostash.it/stash-it-extension.zip
# and stamp its version + size into the unlisted install page served at
# gostash.it/extension (public/extension/index.html).
#
# Run after every extension release, alongside the Web Store upload — the
# hosted zip has gone stale twice by being a separate manual step:
#
#   cd extension && ./scripts/publish-hosted-zip.sh
#
# then commit public/stash-it-extension.zip, public/extension/index.html and
# public/extension/icon128.png. Pushing main deploys them.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."   # extension/

./scripts/package.sh > /dev/null           # builds stash-it-<version>.zip (gitignored)
VERSION=$(node -e "console.log(require('./manifest.json').version)")
SRC="stash-it-${VERSION}.zip"
PUBLIC="../public"
DEST="${PUBLIC}/stash-it-extension.zip"
PAGE="${PUBLIC}/extension/index.html"

[ -f "$SRC" ] || { echo "error: package.sh did not produce $SRC" >&2; exit 1; }
[ -f "$PAGE" ] || { echo "error: install page missing at $PAGE" >&2; exit 1; }

cp "$SRC" "$DEST"
cp icons/icon128.png "${PUBLIC}/extension/icon128.png"

BYTES=$(wc -c < "$DEST" | tr -d ' ')
SIZE_KB=$(( (BYTES + 1023) / 1024 ))

# The page carries two stamp anchors: <span data-version>…</span> and
# <span data-size>…</span>. Rewrite their text; fail loudly if either is gone.
perl -pi -e "s|(<span data-version>)[^<]*|\${1}${VERSION}|; s|(<span data-size>)[^<]*|\${1}${SIZE_KB} KB|" "$PAGE"
grep -q "<span data-version>${VERSION}</span>" "$PAGE" || { echo "error: version stamp not found in $PAGE" >&2; exit 1; }
grep -q "<span data-size>${SIZE_KB} KB</span>" "$PAGE" || { echo "error: size stamp not found in $PAGE" >&2; exit 1; }

echo "Hosted zip refreshed: public/stash-it-extension.zip (v${VERSION}, ${SIZE_KB} KB)"
echo "Install page stamped: public/extension/index.html"
