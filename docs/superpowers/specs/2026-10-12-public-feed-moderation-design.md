# Public feed moderation — findings and proposal (AS-UGC)

**Date:** 2026-10-12 · **Author:** Claude (web/backend) · **Status:** PROPOSAL — awaiting Will's
decisions (§5). Nothing in this document has been built, and public sharing stays exactly as it
is until he decides. Requested by Codex in `docs/agent-coordination.md` (App Store follow-through,
item 3) for the App Store review of the iOS app.

Source audit (read-only, file:line evidence): `/tmp/pw/as-ugc-audit.md` (local; the facts that
matter are repeated here with their references).

## 1. Why this matters for the App Store

Apple's guideline 1.2 expects an app with user-generated content to have (a) a way to filter
objectionable material, (b) a way to report offensive content with timely responses, (c) a way
to block abusive users, and (d) published contact information.

What the iOS app actually does with other people's content: **nothing**. It publishes the
owner's own saves to their public feed and copies feed/share URLs; it never fetches another
user's feed, comments or follows (no reference to `get-public-feed`, `get-discover-feed`,
`get-comments`, `post-comment`, `comments`, `user_follows` anywhere in `ios/`). The social
surfaces live on the web: `/feed/:username`, `/discover`, comments on public items, follows,
and unlisted `/s/<token>` pages.

So the honest App Privacy / age-rating answer is: the app lets a person publish their own content
to a public web page; it does not display other people's content. Whether App Review treats the
web feed as part of the app is their call; the safer posture is to have the web side meet 1.2
before submission, because the account the reviewer creates will have a public feed.

## 2. What exists today (facts)

| Control | Public items | Comments | Profile text | Share links |
| --- | --- | --- | --- | --- |
| Who can post | owner (web, iOS, API) | any session; **the anon key, directly** | owner | owner |
| Filter | none | 9-word spam list (`post-comment`, `get-comments`) | username format only | none |
| Report | none | none | none | none |
| Block / hide / suspend | owner can unshare | owner can switch comments off per item | none | owner stops sharing |

- No `hidden`, `flagged`, `banned` or `suspended` column exists on `items`, `comments` or
  `user_profiles`; `get-public-feed` filters only `user_id` + `is_public`
  (`supabase/functions/get-public-feed/index.ts:61-68`); `get-discover-feed`, `get-comments` and
  `shared_item()` likewise. Admin tooling (`/admin`) is read-only.
- Contact: `hello@gostash.it` is on `/contact`, `/terms`, `/privacy` (static site pages). It is
  **not** linked from the signed-in web app, Settings, `/feed`, `/discover`, `/s` pages, or the
  iOS app on `main` (Codex's candidate 12 adds a Settings contact row). The App Store Connect
  Support URL is the site root. `/contact` has no "report content or a user" reason.
- Terms are silent on comments, other users' content, objectionable material, reporting and
  response time; they do say accounts may be suspended for violations.

## 3. Security findings that are not product decisions (recommend: fix now)

1. **Comment impersonation.** The RLS policy "Anyone can create comments on public items"
   (`supabase/migrations/20250821040218_…sql:5-16`, repeated in `20250821040241_…sql`) has no
   `auth.uid() = user_id` check and no role restriction. Anyone holding the public anon key can
   `POST /rest/v1/comments` with any `user_profiles.id` as the author (ids are published by
   `get-public-feed` and `get-comments`) and skip `post-comment`'s length cap and spam list.
   The web client never inserts directly — it calls `post-comment`, which writes with the
   service role — so **dropping that policy** (or replacing it with
   `auth.uid() = user_id and <item public and comments enabled>`) changes nothing for real users.
   Live policy state to be verified against `pg_policies` before the migration ships.
2. **Anonymous comments from anyone with the anon key.** `post-comment` accepts
   `{ "anonymous": true }` without a session and writes as the shared "anonymous" profile
   (`post-comment/index.ts:66,103-111`); the web UI itself requires sign-in to comment. Decision:
   keep anonymous comments (then rate-limit them) or require a session. **Recommend: require a
   session** — the UI already does, and it removes an unauthenticated write path.
3. Smaller, same family: `get-public-feed` returns every item column (page body, summary,
   attributes, share token) for public items; `limit`/`offset` are uncapped. Worth trimming when
   the feed function is next touched; not a 1.2 item.

## 4. Options for guideline 1.2

### Option A — minimum credible kit (recommended before submission; ~1.5 days web/backend)

- **(d) Contact, everywhere it is missing:** "Contact" in the signed-in header menu and in
  Settings; a footer line on `/feed`, `/discover` and `/s`; a "Report content or a user" reason on
  `/contact`; App Store Connect Support URL → `https://www.gostash.it/contact`. iOS Settings
  contact row is Codex's (candidate 12).
- **(b) Report:** `content_reports` table (reporter nullable, `item_id` / `comment_id` /
  `reported_user_id`, reason, note, status, timestamps) written through one rate-limited edge
  function `report-content` that also emails `hello@gostash.it` (Resend is already wired for
  reminders); a "Report" entry in the public card menu, on each comment row and in the `/s`
  header. Response-time wording in Terms is Will's (e.g. "we review reports within N days").
- **(a) Filter + (c) operator block:** `hidden_at` on `items` and `comments`, `suspended_at` on
  `user_profiles`; `hidden_at is null` / owner-not-suspended predicates added next to `is_public`
  in `get-public-feed`, `get-discover-feed`, `get-comments`, `shared_item()` and the RLS read
  policies; `admin-stats` actions `hide_item`, `hide_comment`, `suspend_user` (the `admin_users`
  gate already exists) plus GoTrue `ban_duration` so a suspended account cannot sign in. Optional
  automated screen: the OpenAI moderation endpoint on comment text and on an item's title/note
  when it flips public (OpenAI is already a listed processor).
- **(c) user block (optional in this tier):** `user_blocks(blocker_id, blocked_id)`; "Block" on a
  comment and on a feed header; filters that viewer's comments and Discover; a
  `remove_follower` RPC.

### Option B — narrow the product until A exists

Turn off the two features that put strangers' content in front of each other — comments and
`/discover` — leaving the per-user feed and share links (broadcast-only, owner-controlled). This
is a visible product change for existing users and only reduces, not removes, the 1.2 surface
(public feeds still exist). **Not recommended on its own**; it could be a stopgap if the
submission date comes before A.

### Option C — do nothing beyond §3 and contact links

Submit with the truthful statement that the app does not display other users' content. Cheapest;
risk is a 1.2 rejection or a reviewer question once they find the web feed. Not recommended.

## 5. Decisions for Will

1. Ship §3 (1) now as a backend security fix? (Recommend yes; no user-visible change.)
2. Anonymous comments: keep (and rate-limit) or require sign-in? (Recommend require sign-in.)
3. Option A / B / C for 1.2, and whether user-block is in scope for the first pass.
4. Is `hello@gostash.it` monitored, and what response time can Terms promise?
5. Terms additions (objectionable content, comments, reporting) — wording is legal copy; I can
   draft from the existing Terms once 3–4 are decided.

## 6. Contracts Codex would consume (only if Option A is chosen)

- `POST /report-content` `{ item_id? | comment_id? | reported_user_id?, reason, note? }` →
  `201 { id }`; anon key allowed (rate-limited), session optional.
- Feed/comment reads gain the hidden/suspended predicates server-side; clients change nothing.
- iOS: no native report/block UI is required while the app shows no third-party content; a
  Settings contact row and the Support URL cover (d).
