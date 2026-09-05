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
