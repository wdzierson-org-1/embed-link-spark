# Stash it — Chrome extension

One-click capture into [Stash](https://www.gostash.it). Manifest V3, plain
JavaScript, **no build step and no dependencies** — the directory loads as-is.

## Install (unpacked)

1. Open `chrome://extensions`, enable **Developer mode** (top right).
2. **Load unpacked** → pick this `extension/` directory.
3. Pin **Stash it** to the toolbar (puzzle-piece menu → pin).
4. Click the toolbar button once — it opens the sign-in page. Sign in with
   your Stash email/password. After that, saving is one click forever.

## What it does

| Gesture | Result |
|---|---|
| Click the toolbar button | Current page saved as a link (`add-url`) |
| Right-click selected text → **Stash it** | Selection saved as a note (`add-note`) |
| Right-click an image → **Stash it** | The image itself uploaded and saved (`add-file`) |

Feedback is a small badge on the toolbar icon, scoped to the tab you saved
from: `…` while saving, green `✓` for ~2s on success, red `!` for ~4s on
failure. Nothing is injected into the page.

By design there is **no annotation UI** — capture is zero-input. Add context
to any item later at gostash.it. Titles, descriptions, OCR, transcripts, and
embeddings are enriched server-side after the save returns.

## Architecture

| File | Role |
|---|---|
| `manifest.json` | MV3 manifest |
| `background.js` | Service worker: menus, toolbar action, badge feedback |
| `stash-api.js` | Auth (GoTrue REST, session in `chrome.storage.local`, refresh-on-demand with single-flight) + `add-url`/`add-note`/`add-file` + Storage upload |
| `lib.js` | Pure helpers (mime/extension resolution, URL checks) — node-testable |
| `signin.html/js/css` | Sign-in page; also the options page |
| `icons/` | Toolbar icons; `icon-src.html` regenerates them (instructions inside) |

Auth deliberately avoids supabase-js: MV3 service workers sleep between
events, which kills refresh timers, so the robust pattern is
refresh-on-demand (refresh when <60s of token life remains, plus one retry
on 401). The raw REST token endpoint is a sanctioned path per
`docs/PLATFORM_API.md`.

## Permissions rationale

- `contextMenus`, `storage` — the feature itself.
- `scripting` — reads the exact selection from the page, because Chrome's
  `selectionText` collapses newlines. Falls back to `selectionText` where
  injection is blocked (PDF viewer, chrome:// pages).
- `<all_urls>` — fetching right-clicked image bytes from any site (with that
  site's cookies, so auth-gated images work) and reading the active tab URL.

## Tests

```sh
cd extension && npm test   # node --test, no deps
```

## Known limits (v1)

- Images over 20 MB are rejected (mirrors the web app's cap).
- `blob:` image URLs can't be fetched from a service worker → red `!`.
- Non-image bytes behind an image URL (CDN error pages) fail on purpose
  rather than saving garbage.
- No offline queue — a failed save just shows `!`; retry when back online
  (the iOS share extension's Outbox pattern is the reference if this ever
  matters on desktop).
- Chrome/Chromium only (Arc, Brave, Edge work — anything that loads MV3).
