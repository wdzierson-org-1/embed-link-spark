#!/bin/sh
# Renders the composed sample objects in this folder to ../img with headless Chrome.
# Usage: sh asset-src/build.sh   (from the prototype folder or anywhere)
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
OUT="$HERE/../img"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

shot() { # name width height scale
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files \
    --virtual-time-budget=4000 --force-device-scale-factor="$4" --window-size="$2,$3" \
    --screenshot="$OUT/$1.png" "file://$HERE/$1.html" 2>/dev/null
}

shot moodboard 1200 900 1
shot shot-colette 390 844 2
shot paper 612 792 1.5
shot repo 900 620 1
# The phone's Photos grid: screenshots shown small (grid cell, share thumb, library card), so 1×.
shot shot-maps 390 844 1
shot shot-thread 390 844 1
shot shot-receipt 390 844 1
shot shot-boarding 390 844 1
shot shot-messages 390 844 1

# Anything with a photo in it, and the Photos-grid screenshots, ships as JPEG; other flat
# UI-like renders stay PNG.
for f in moodboard shot-colette shot-maps shot-thread shot-receipt shot-boarding shot-messages; do
  sips -s format jpeg -s formatOptions 82 "$OUT/$f.png" --out "$OUT/$f.jpg" >/dev/null
  rm "$OUT/$f.png"
done
ls -la "$OUT"
