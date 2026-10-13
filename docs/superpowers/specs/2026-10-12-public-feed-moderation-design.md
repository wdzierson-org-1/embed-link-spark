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

### Option A — the complete kit (recommended before submission; ~4 days web/backend; nothing removed)

*Revised 2026-10-12 after Codex's review: guideline 1.2 lists four things an app with
user-generated content must have — filtering objectionable material **before** it is posted,
reporting with timely responses, blocking abusive users, and published contact — and each is a
required part of this option. Nothing below is optional, and no existing feature is switched off.*

- **(a) Filter objectionable material before it is posted.**
  - *Comments:* `post-comment` runs the text through OpenAI's moderation endpoint
    (`omni-moderation-latest`; OpenAI is already a listed processor) before the insert and refuses
    a flagged comment with `400 { error: "rejected" }`. If the moderation call itself fails the
    comment is refused too (fail closed: a comment can be retried, an unchecked one cannot be
    unpublished). The direct-insert path is already closed to anyone but the signed-in author
    (§3), so the function is the only write path that matters.
  - *Public items:* clients flip `items.is_public` directly through RLS today, so the check has to
    be server-side and asynchronous. A trigger on `items` (`is_public` turning true, or a public
    item's title / note / sticky note / file changing, or a share token being minted) sets a new
    `items.moderation` column to `'pending'` and enqueues the item; a worker in the
    `enrichment-maintenance` cron shape (every minute) sends the title, the person's note, the
    sticky note and — for pictures — the image to the moderation endpoint and settles the row to
    `'clear'` or `'rejected'` (+ `hidden_at`). `get-public-feed`, `get-discover-feed`,
    `get-comments`, `shared_item()` and the public RLS read policy add `moderation = 'clear'`
    beside `is_public`. For the person this means an item appears publicly a few seconds after
    they publish it; the card shows "publishing…" meanwhile (web and iOS: one optional label; the
    publish controls do not change). A rejected item stays in the owner's library, visibly marked,
    with "Report a mistake" (an appeal through `report-content` on their own item). Items already
    public today are checked once by a backfill before launch — a rejection is a visible state on
    the owner's card, never a silent disappearance.
  - *Profile text* (display name, bio) gets the same trigger + worker check on write; usernames
    are already format-locked.
- **(b) Report, and respond in time.** `content_reports(id, reporter_id?, item_id?, comment_id?,
  reported_user_id?, reason, note, status: open | resolved | dismissed, created_at, resolved_at,
  resolved_by, action)`, written only through a new `report-content` function (anon key allowed,
  5 reports per minute per IP, session optional), which also emails `hello@gostash.it` with the
  links (Resend is already wired for reminders). UI: "Report" in the public card menu, on each
  comment row, in the `/s` header and on a feed header ("Report this user"); a "Report content or
  a user" reason on `/contact` and `/support`. Response: the operator workflow (§6) commits to a
  first action within one business day — the number is Will's; Apple only says "timely" — the
  report's status and action are stored, and the reporter gets one email when it is resolved.
- **(c) Block abusive users — both directions.**
  - *Person-level:* `user_blocks(blocker_id, blocked_id, created_at)`; "Block" on a comment row
    and on a feed header. Effects: the blocked person's comments and public items leave the
    blocker's feed / Discover / comment reads; the blocked person cannot comment on the blocker's
    items (checked in `post-comment`); any follow between them is removed (a `remove_follower`
    RPC also lets anyone drop a follower). Unblock under Settings → Your information → Blocked
    people.
  - *Operator-level:* `user_profiles.suspended_at`; every public read excludes a suspended owner's
    items and comments; `post-comment` refuses them; GoTrue `ban_duration` stops sign-in. Actions
    `hide_item`, `hide_comment`, `suspend_user` and their `restore_*` counterparts go through
    `admin-stats` (the `admin_users` gate exists) and every action is written to
    `moderation_actions(who, what, target, report_id, at)`.
- **(d) Contact.** "Contact" in the signed-in header menu and in Settings; a footer line on
  `/feed`, `/discover` and `/s`; `/support` (drafted) as the App Store Support URL; the iOS
  Settings contact row is Codex's (candidate 12).

Effort: moderation calls + trigger/worker + read predicates ≈ 2 days; reports table / function /
UI / email ≈ 1 day; blocks + suspension + admin actions ≈ 1 day; backfill and QA ≈ ½ day. iOS
needs no report/block UI while it shows no third-party content; the optional "publishing…" label
and the Settings contact row are its only touch points.

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

1. §3 (1) was applied in production on 2026-10-12 as a security fix (migration
   `20261012220000`); nothing to decide.
2. Anonymous comments: keep (and rate-limit) or require sign-in? (Recommend require sign-in.)
3. Option A (complete, above) / B / C for guideline 1.2.
4. Is `hello@gostash.it` monitored, and what first-response time can Terms and the operator
   workflow promise? (The drafts below say one business day.)
5. The Terms additions drafted in §7 — legal copy for Will to edit or reject; nothing is
   published until he says so.

## 6. Operator workflow (draft — Will confirms the mailbox and the time)

1. A report arrives as an email to `hello@gostash.it` and as an open row in `content_reports`.
   Whoever is on support opens `/admin/moderation` (new admin page: open reports, oldest first,
   each with the reported item, comment or profile and the reporter's note).
2. Within one business day, judge the content against the Terms (§7). Each action is one click
   and is logged: hide the item or comment (the owner keeps it in their library, marked "hidden by
   Stash — see the Terms"), suspend the account (sign-in blocked, all public content hidden), or
   dismiss. Content that may be illegal is hidden first; any legal duty is handled separately.
3. Email the reporter the outcome in one line, without details about the other person. Email the
   owner when their content is hidden or their account suspended, with the reason and how to
   appeal (reply to that email).
4. An appeal reply reopens the report; a second person (or Will) decides. A suspension is lifted
   by clearing `suspended_at` and the sign-in ban.
5. Three upheld reports against one account in 90 days → suspension (Terms §7).
6. Weekly, skim the automated rejections (`moderation = 'rejected'`) for false positives and
   restore them.

## 7. Terms additions (draft legal copy for Will — not published)

- **What you may publish.** "Items you mark public, share links you create, your profile and your
  comments are visible to other people. Don't publish content that is illegal, that infringes
  someone's rights, that harasses or threatens anyone, that is sexually explicit, or that exposes
  someone's private information."
- **Checks before publishing.** "Public items and comments are checked by an automated filter
  before they appear, and may be refused or held. We may hide content that breaks these terms;
  you keep a private copy in your own library."
- **Reporting.** "Anyone can report an item, a comment or a person from the content itself or by
  writing to hello@gostash.it. We review reports and take a first action within one business
  day." *(the time is Will's)*
- **Blocking.** "You can block a person: their comments and public items disappear from your
  view, they can no longer comment on your items, and any follow between you is removed."
- **Suspension and appeal.** "We may suspend an account that breaks these terms, usually with
  notice and always with a way to appeal by email. Three upheld reports in ninety days lead to
  suspension."
- The existing clauses — the licence for public items (§ "for items you explicitly mark public"),
  the prohibition on illegal or infringing content, and the suspension right — stay as they are.

## 8. Contracts Codex would consume (only if Option A is chosen)

- `POST /report-content` `{ item_id? | comment_id? | reported_user_id?, reason, note? }` →
  `201 { id }`; anon key allowed (rate-limited), session optional.
- Public reads (`get-public-feed`, `get-discover-feed`, `get-comments`, `shared_item()`, RLS)
  gain `moderation = 'clear'` and the hidden / suspended / blocked predicates server-side;
  clients change nothing to keep working.
- `items.moderation` (`pending | clear | rejected`) is readable by the owner; a client may show
  "publishing…" / "rejected — report a mistake" on the card. Optional.
- `user_blocks` through two RPCs, `block_user(id)` / `unblock_user(id)`, and `remove_follower(id)`.
- iOS: no native report or block UI is required while the app shows no third-party content; the
  Settings contact row and the Support URL cover (d).
