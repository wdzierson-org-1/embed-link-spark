# Chrome Web Store listing copy

Paste these fields into the CWS Developer Dashboard's **Store listing** tab
verbatim. Nothing here should be edited to sound more "marketing" than the
product is — Stash's whole pitch is that capture is boring and instant.

## Name

```
Stash it
```

Matches `manifest.json`'s `name` field exactly (CWS requires this).

## Summary (single line, shown in search results and the store card)

Character count: 102 / 132 max.

```
Save pages, selected text, and images to your Stash in one click — no forms, no folders, just capture.
```

## Category

**Productivity** (CWS's closest fit — the extension is a capture tool, not a
"Tools" utility that changes browser behavior).

## Language

**English (en)** — the only language the extension and its listing ship in.

## Full description

```
Stash it saves things to your Stash — the personal capture app at gostash.it
— in one click, with nothing to fill in.

WHAT IT DOES

• Click the toolbar button to save the page you're on as a link.
• Right-click any selected text and choose "Stash it" to save it as a note.
• Right-click any image, on any site, and choose "Stash it" to save the
  image itself — not a link to the page it's on.

That's the entire interaction. There's no popup to configure, no folder to
choose, no tags to type. You save, and a small checkmark on the toolbar icon
confirms it landed. Everything else — a title, a description, a summary, a
transcript, OCR text, search embeddings — is generated automatically on the
Stash servers after the save completes, so the extension itself stays instant
and dumb by design.

WHO IT'S FOR

Anyone using Stash (gostash.it) as their capture inbox for links, quotes,
and images found while browsing, who wants that capture to take one click
instead of a copy-paste-switch-tabs-paste round trip. You'll need a Stash
account — sign up free at gostash.it, then sign in once from the extension's
options page.

WHY IT NEEDS BROAD SITE ACCESS

The image-save feature works by fetching the image's bytes directly from
wherever it's actually hosted — which, on most sites, is a different domain
than the page you're looking at (a CDN, a media host, etc.). That fetch has
to carry that host's own cookies to work on any site that gates its images
(private galleries, logged-in-only content), and it can be triggered from
any site since it responds to a right-click, not a fixed list of domains.
That's the only thing the extension's site access is used for — see the
"Permissions" section of this listing (and permissions-justifications.md in
the source repo) for the full, evidence-backed breakdown of every permission
requested.

WHAT IT DOESN'T DO

No ads, no analytics, no tracking pixels, no third-party SDKs. No page
content is read except the exact text you've selected (to save it as a
note) and the URL of an image you've right-clicked (to fetch and save it).
Nothing is injected into any page's UI. The only network calls the extension
makes are to Stash's own backend (gostash.it / Supabase) to sign you in and
save what you asked it to save.

Source: the extension is plain JavaScript, no build step, no bundler,
readable end to end in the unpacked source.
```

## Notes for whoever pastes this in

- The CWS dashboard may show its own character counts that differ slightly
  from a plain `wc -c` (it sometimes counts by UTF-16 code units) — the
  102-char summary above has ~30 characters of headroom, so it should clear
  any reasonable counting method.
- Keep the promotional screenshot (`screenshots/04-promo.png`) as the first
  image in the gallery — CWS uses the first screenshot as the default
  storefront hero.
