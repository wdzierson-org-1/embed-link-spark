# Chrome Extension: Web Store Submission Prep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the "Stash it" extension Chrome-Web-Store-ready: minimal permissions (`activeTab` instead of `<all_urls>` if behavior allows), a complete store-listing package (copy, screenshots, permission justifications, data-use disclosures), a submission zip, and a step-by-step runbook for the parts only Will can do (developer account, first upload).

**Spec:** `extension/` (MV3, plain JS, no build step; tests `cd extension && npm test`), CWS policies (single purpose, minimal permissions, accurate listing), `docs/ETHOS.md` (lowest-friction capture), the live `/privacy` page.

## Global Constraints

- Worktree `.claude/worktrees/ext-cws-submission` (base = main `c8b6405`): commit, never push; audit origin/main at wrap. Extension tests must stay green (`cd extension && npm test`); web `npm test` untouched.
- **Permissions goal:** drop `host_permissions: ["<all_urls>"]` → `"permissions": ["contextMenus", "storage", "scripting", "activeTab"]`. `activeTab` grants temporary host access on toolbar click AND context-menu invocation — read `extension/background.js` end-to-end first; this works ONLY if every `chrome.scripting.executeScript`/tab access targets the tab the user just clicked on. If ANY flow needs access beyond the invoking tab (verify honestly), keep the minimal explicit host list instead and document why. Bump `version` to `1.2.0` on any manifest change. Full regression: the extension's own test suite + a LIVE check (load unpacked via `chrome --load-extension`, exercise: toolbar click saves the page; context menu on selected text; context menu on an image — REST-verify each item landed via the uitest account creds in ios/.env.test.local, clean up rows with proof).
- **Store package** (new `extension/store/` folder, committed): `listing.md` (name "Stash it", ≤132-char summary, full description written from the README/ETHOS — capture-first, no hype; category Productivity/Tools; language en), `permissions-justifications.md` (one paragraph per permission for the dashboard form incl. remote-code "No", data-use disclosures: account auth token + saved content sent to gostash.it backend, no sale/no third parties — map to CWS's data-use checkboxes), `SUBMISSION.md` runbook (Will's steps: register CWS dev account $5 at chrome.google.com/webstore/devconsole with his Google account; create item; upload zip; paste listing/justifications; set privacy policy URL https://www.gostash.it/privacy; visibility Public (or Unlisted first — recommend Unlisted for a soft launch, Will's call); submit — typical review a few days), and screenshots.
- **Screenshots (1280×800 PNG, ≥1 required, up to 5):** REAL captures preferred — launch Chrome with `--load-extension` + a fixed window size, capture: (1) context menu "Stash this page" over a real article, (2) the signin/options page, (3) a saved-confirmation state; plus compose (4) one clean promo frame (1280×800 HTML render: wordmark + one-line value prop + a screenshot inset — flat brand rules, ink on white, no gradients per DESIGN.md brand rule). Verify each is exactly 1280×800, READ them.
- **Zip:** `extension/scripts/package.sh` (new, committed): zips manifest + sources + icons EXCLUDING test/, package.json, node_modules, store/ → `stash-it-<version>.zip`; verify the zip loads unpacked-equivalent (unzip to temp, load, smoke). Also refresh the hosted copy convention: note in SUBMISSION.md that gostash.it/stash-it-extension.zip should track releases (don't modify the hosted one this round).
- Docs at wrap: `docs/ui-changes.md` entry (permissions narrowed to activeTab — behavior identical from the user's view; store prep); plan outcome. No iOS files touched.

## Tasks

### Task 1: Permissions hardening + live regression
Read background.js/lib.js/stash-api.js fully; make the activeTab call (or documented fallback); bump version; extension tests green; live load-unpacked regression of all three capture flows with REST verification + cleanup; commit.

### Task 2: Store package (listing, justifications, runbook, screenshots, zip script)
Everything under Global Constraints "Store package"/"Screenshots"/"Zip"; screenshots READ; zip smoke-tested; commit.

### Task 3: Review + wrap
Fresh reviewer: policy-compliance pass (single purpose, permission minimality vs code reality, listing accuracy vs actual behavior, screenshot dimensions, justifications completeness, zip contents exact); then docs entry + outcome; suites (extension npm test; web npm test untouched-but-run); merge-audit; hand back for merge. NOTE: no store upload happens from here — the runbook + Will's account do that.

## Outcome (2026-09-05)

Commits: `75a6e57` (permissions hardening), `f9c7bee` (store package), plus
this docs commit. Reports: `.superpowers/sdd/ext-cws/task-{1,2,3}-report.md`.

**Permissions decision (activeTab-fallback):** `activeTab` was evaluated
first per the plan's instruction but doesn't cover real behavior — the
image-save flow (`stashImage` in `stash-api.js`) is a credentialed
cross-origin `fetch` from the service worker straight to the image's own
host, routinely a different origin than the page (CDN-hosted images).
`activeTab`'s grant only covers the invoking tab's top-level origin, not
third-party origins referenced inside that page. **Evidence, one line:**
curl against real image CDNs (Wikimedia, Unsplash, jsDelivr, NYT) shows
`Access-Control-Allow-Origin: *` with no `Access-Control-Allow-Credentials`
— a credentialed fetch fails CORS there per spec — confirmed live in a
loaded extension where the identical image fetch failed under a real,
freshly-granted `activeTab` grant and succeeded only once `host_permissions`
covered `http://*/*`+`https://*/*`. Fallback shipped: narrowed explicit host
list (drops `<all_urls>`'s `file://`/`ftp://`/other non-web schemes; every
real capture flow unaffected).

**Review verdict (Task 3, skeptical CWS-policy pass):** approved to submit,
with one honest risk called out below.

- Single purpose: confirmed — every `chrome.*`/`fetch` call site
  (background.js, lib.js, stash-api.js, signin.js, read in full) serves
  "capture to Stash" (toolbar save, selection note, image save, sign-in,
  badge feedback). No dormant capability, no analytics/tracking, no unrelated
  code paths.
  - Re-verified the manifest against a fresh grep of every `chrome.*` call:
    `contextMenus`, `storage`, `scripting`, `action` (no permission needed),
    `runtime` (no permission needed), `tabs.create` (no `tabs` permission
    needed for `.create` with a static URL) — matches the declared
    `permissions` exactly, nothing extra, nothing missing.
  - `scripting` + the broad host list are both independently load-bearing:
    `scripting` gates the `chrome.scripting.executeScript` API itself;
    `host_permissions` is what lets that injection target arbitrary tabs
    (and, separately, is what the credentialed image fetch needs to bypass
    CORS). Adding `activeTab` on top would be redundant, not additive — CWS
    reviewers scope their scrutiny to the *broadest* grant, and
    `host_permissions: http(s)://*/*` already is that; `activeTab` wouldn't
    narrow it or change the review story.
- Listing accuracy: `listing.md`'s description matches actual behavior
  line-for-line (three save gestures, no popup/config, server-side
  enrichment framing matches ETHOS, "why broad host access" paragraph
  matches the real CORS reasoning). Summary verified 102 Unicode characters
  (`wc -m`) against the ≤132 budget.
- Justifications: `permissions-justifications.md` maps one-to-one onto CWS's
  actual dashboard fields (per-permission justification, remote-code
  question, data-use checkboxes table, single-purpose statement, privacy URL)
  — actionable verbatim, confirmed by reading `SUBMISSION.md`'s own
  field-by-field paste instructions against it.
- Screenshots: all 4 re-verified exactly 1280×800 via `sips`; all 4 read
  visually. The real capture's email mask (`you@yourdomain.com` swapped for
  the live test account's address) reads as a natural placeholder, not a
  visible edit. The two composed/illustrative ones (badge confirmation,
  native image context menu) are visually faithful to the actual code paths
  (badge text/color/duration match `background.js`'s `badge()` helper; the
  context-menu mock's item list and "Stash it" position match real Chrome
  extension-menu placement) and are disclosed as illustrative in both the
  Task 2 report and this outcome.
- Zip: rebuilt fresh via `package.sh` — 14 files (manifest, background.js,
  stash-api.js, lib.js, signin.{html,js,css}, README.md, icons/*), version
  1.2.0, no `test/`/`store/`/`scripts/`/`package.json`/`node_modules`
  leakage. Minor, out-of-scope nit noted, not fixed: `icons/icon-src.html`
  (a pre-existing dev-only icon-generation source, not new to this plan)
  ships inside the zip because the whole `icons/` folder is included
  per-spec — harmless (no code execution, no PII, ~1KB static HTML) but
  technically not a "runtime" file.
- `SUBMISSION.md`: cold-runnable — covers dev-account registration/fee,
  zip build/upload, every dashboard tab (listing, privacy practices,
  distribution/visibility), status/notification surfaces, and the
  future-update path. No missing dashboard field found.

**Honest odds on the broad-host review:** CWS explicitly flags broad
host-permission items for closer manual review (this plan's own risk to
carry, not new information). The justification is strong (concrete,
evidence-backed, ties directly to an observable, singular feature — not
boilerplate), and the permission set is already narrower than `<all_urls>`.
Read as "likely to pass, plausibly with one review round-trip if a human
reviewer wants to see the image-save behavior demonstrated" rather than a
sure first-pass approval — broad host permissions on a small, first-time
developer-account listing are exactly the profile CWS's manual reviewers
scrutinize hardest, regardless of justification quality.

**Fixed during this task (disclosed):** a stray duplicated "pe" typo
introduced while drafting the `docs/ui-changes.md` entry, corrected before
commit. No code or store-package files were changed.

**Suites:** `cd extension && npm test` — 15/15 passing. Root `npm test` —
33 files / 202 tests passing, untouched (no web source files touched by
this plan).

**Merge audit:** `git fetch origin` — `HEAD..origin/main` empty, nothing to
merge, no re-test needed.

**What remains:** only Will's steps per `SUBMISSION.md` — register the $5
CWS developer account, upload the zip, paste the listing/justification copy
into the dashboard, and submit.
