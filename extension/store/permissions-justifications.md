# Permissions justifications (Chrome Web Store dashboard → Privacy practices)

Manifest (`extension/manifest.json`, v1.2.0):

```json
"permissions": ["contextMenus", "storage", "scripting"],
"host_permissions": ["http://*/*", "https://*/*"]
```

Paste the paragraph below each permission into the matching justification
field in the dashboard's "Permissions" tab. Each one names the single
user-visible feature it exists for — CWS reviewers reject listings where a
permission's justification doesn't map to something the reviewer can
actually see the extension do.

## `contextMenus`

Adds the two "Stash it" entries to the right-click menu — one that appears
when text is selected, one that appears on images. This is one of the
extension's three save gestures (the other is the toolbar button); without
this permission the right-click save paths don't exist at all.

## `storage`

Holds the signed-in session (access token, refresh token, expiry) in
`chrome.storage.local` so the user signs in once and every future save is a
single click, and stores nothing else — no browsing history, no page
content, no settings beyond the session.

## `scripting`

Reads the user's exact text selection from the page (`window.getSelection()`)
when they right-click → "Stash it" on selected text. This exists because
Chrome's built-in `info.selectionText` (passed to the context-menu handler
for free, no permission needed) collapses newlines and can truncate long
selections — `scripting` lets the extension read the real, complete
selection instead. It runs only in the tab the context menu was invoked on,
only in response to that click, and only to read text the user just
selected; it never modifies the page or runs on a schedule.

## Host permissions — `http://*/*`, `https://*/*`

**Leads with the feature:** this is what makes "right-click any image on any
site and save the image itself" work, and it's core, load-bearing product
behavior, not an edge case — there's no way to offer that feature against an
enumerable list of hosts, because the image can be hosted anywhere.

**The one-sentence evidence:** real CORS checks against major image CDNs
(Wikimedia, Unsplash, jsDelivr, NYT) show they return
`Access-Control-Allow-Origin: *` with no `Access-Control-Allow-Credentials`,
which per the Fetch spec means a cookie-carrying (`credentials: 'include'`)
request to fetch the image bytes is rejected by CORS unless the extension's
own host permissions cover that origin directly (bypassing CORS negotiation
entirely, which is what `host_permissions` is for) — confirmed empirically
with a live loaded build: the identical image-fetch call failed with
`Failed to fetch` under a narrower grant (including a fresh, real
`activeTab`-style grant on the invoking tab) and succeeded only once
`host_permissions` covered the image's own origin.

**What's excluded on purpose:** this is `http://*/*` + `https://*/*`, not
`<all_urls>` — it deliberately drops `file://`, `ftp://`, and other
non-web schemes, none of which Stash ever touches. Every other place the
extension touches a tab (the toolbar-click save, the context-menu selection
read) only ever targets the single tab the user just interacted with; the
host permission's only real job is the cross-origin image fetch described
above.

## Remote code

**No.** The extension ships no remote-loaded or eval'd code. It's plain,
unminified JavaScript, no bundler, no build step — every file that runs is
in the unpacked package under review. The only network calls are `fetch()`s
to Stash's own backend (Supabase auth + the platform capture endpoints) and,
for the image-save feature, to whatever origin hosts the right-clicked
image; none of those responses are ever executed as code.

## Data use disclosure (CWS "Data usage" tab — check the boxes this maps to)

| CWS data category | Collected? | What / why |
|---|---|---|
| Personal communications | No | — |
| Financial and payment information | No | — |
| Health information | No | — |
| Personal identifiers (email) | **Yes** | The Stash account email, used only to authenticate the user against their own Stash account. |
| Authentication information | **Yes** | Session/refresh tokens, stored locally (`chrome.storage.local`) and sent to Stash's own backend to keep the user signed in. |
| Website content | **Yes** | Exactly what the user chooses to save: the current page's URL (toolbar save), the exact selected text (note save), or the right-clicked image's bytes (image save). Nothing else on the page is read. |
| Web browsing history | No | The extension never reads tab history, only the URL/content of the tab the user actively invoked a save from. |
| Location | No | — |
| Other | No | — |

**Certifications to check:**
- Data is **not sold** to third parties.
- Data is **not used or transferred for purposes unrelated to the item's
  single purpose** (all of it — auth token, saved URL/text/image — goes to
  Stash's own backend to fulfill the save the user just asked for, and
  nowhere else).
- Data is **not used or transferred to determine creditworthiness or for
  lending purposes**.

**Single purpose statement** (dashboard field): *Save the page, selected
text, or image the user chooses to Stash's own backend, on a single click or
right-click — nothing else.*

**Privacy policy URL:**

```
https://www.gostash.it/privacy
```
