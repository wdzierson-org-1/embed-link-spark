# Chrome Web Store submission runbook (Will's steps)

Everything in `listing.md` and `permissions-justifications.md` is
copy-paste-ready. The zip is built by `extension/scripts/package.sh`. This
doc is the sequence of clicks nobody but you (an authenticated Google
account holder with a credit card for the one-time fee) can do.

## 0. One-time: register a developer account

1. Go to <https://chrome.google.com/webstore/devconsole>.
2. Sign in with the Google account you want to publish as (this becomes the
   public "developer" identity on the listing — consider whether that
   should be a personal or a Stash-branded Google account before doing
   this step; it's awkward to change later).
3. Pay the one-time **$5 USD** registration fee if you haven't registered a
   CWS developer account before.
4. Accept the Developer Agreement.

## 1. Build the zip

```sh
cd extension
./scripts/package.sh
```

This produces `stash-it-1.2.0.zip` in `extension/` (gitignored — see
"Future updates" below for why it isn't committed). Bump `version` in
`manifest.json` before re-running this for any future release; the script
names the zip after whatever version is currently in the manifest.

## 2. Create the item

1. In the Developer Dashboard, click **New item**.
2. Upload `stash-it-1.2.0.zip`. The dashboard unpacks it and validates the
   manifest — it should show name "Stash it", version "1.2.0", and no
   manifest errors. If it flags a permission warning, that's expected for
   the broad host permission; the justification you paste in step 4 is what
   satisfies the reviewer, not the dashboard's own linter.

## 3. Store listing tab

Paste from `listing.md`:

| Dashboard field | Source |
|---|---|
| Description | The "Full description" block |
| Category | Productivity |
| Language | English |
| Screenshots | All four PNGs in `store/screenshots/` — order: `04-promo.png` first (it becomes the storefront hero), then `01-options-signed-in.png`, `03-context-menu-image-save.png`, `02-saved-confirmation.png`. All are 1280×800; the dashboard should accept them without complaint. |

The dashboard's "Store listing" tab doesn't have a separate "Name" or
"Summary" field distinct from the manifest/description in the current CWS
UI revision — if you do see a short-summary field (some rollout cohorts
have it), use the 102-character summary line from `listing.md`.

## 4. Privacy practices tab

1. **Single purpose**: paste the single-purpose statement from
   `permissions-justifications.md`.
2. **Permission justifications**: one field per permission
   (`contextMenus`, `storage`, `scripting`, and the host permission) —
   paste the matching paragraph from `permissions-justifications.md` into
   each.
3. **Are you using remote code?**: **No.**
4. **Data usage**: check the boxes per the "Data use disclosure" table in
   `permissions-justifications.md` (personal identifiers, authentication
   information, website content — nothing else), and check the three
   certifications (not sold, not used for unrelated purposes, not used for
   credit/lending decisions).
5. **Privacy policy URL**: `https://www.gostash.it/privacy`

## 5. Distribution / visibility

**Recommendation: start with Unlisted.** It's installable by anyone with the
direct link (so you can hand it to yourself, testers, or anyone you send the
URL to) but won't appear in Chrome Web Store search — a soft launch with a
rollback-free way to fix anything a first real reviewer catches, before it's
discoverable. Flip it to **Public** once you're confident in it (Dashboard →
item → Distribution → Visibility — no re-review is required just to change
visibility, only for actual content/code changes).

This is your call to make either way — Unlisted-first is the safer default,
not a requirement.

## 6. Submit for review

Click **Submit for review**. Chrome Web Store's own guidance is **most
reviews resolve within a few days**; extensions requesting broad host
permissions (ours does, for the reason documented in
`permissions-justifications.md`) sometimes take longer because they get a
closer manual look. There's no way to expedite from the dashboard.

## Where to check status / get notified

- **Dashboard → your item** shows a status pill: *Draft* → *Pending review*
  → *Published* (or *Rejected* with a reason, in which case the item stays
  in draft until you fix and resubmit).
- Google emails the account used to register the developer account for:
  submission confirmation, approval, rejection (with the specific policy
  cited), and any later re-review triggered by a manifest/permission
  change.
- The dashboard also has a **"Content and privacy"** or **"Compliance"**
  panel that surfaces the same automated pre-checks the reviewer's tooling
  runs (permission-vs-code-behavior mismatches, missing privacy policy,
  etc.) — worth checking before submitting, since it catches some issues
  before a human reviewer does and doesn't cost you a review cycle.

## Future updates (after this first submission)

1. Bump `version` in `extension/manifest.json` (Chrome requires every
   uploaded package to have a strictly higher version than the last
   published one).
2. Re-run `./scripts/package.sh` — it names the zip after the new version.
3. Dashboard → your item → **Package** → upload the new zip → **Submit for
   review**. Listing copy, screenshots, and privacy answers persist across
   versions unless you changed something that needs a new justification
   (e.g. a new permission).
4. `docs/ui-changes.md` gets the dated entry for whatever shipped, same as
   every other platform change — this isn't CWS-specific, just the repo's
   standing rule.

**Automating this later:** Google publishes a [Chrome Web Store Publish
API](https://developer.chrome.com/docs/webstore/using_webstore_api) (OAuth2,
`chromewebstore.googleapis.com`) that can upload a new package and submit it
for review from a script/CI job instead of the dashboard UI. Worth wiring up
once releases are frequent enough that the manual upload becomes the
bottleneck; out of scope for this first submission, which has to happen
through the dashboard by hand regardless (only Will can create the item and
accept the developer agreement the first time).

## Hosted zip convention

`gostash.it/stash-it-extension.zip` is a separate, informal "grab it here"
link (referenced from marketing/help copy, not from the CWS listing itself)
that should track whatever's actually published. This round doesn't touch
that hosted copy — flagging it here so the next person who ships a version
bump remembers to refresh it, not just the CWS package.
