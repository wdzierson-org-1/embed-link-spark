# Chat sessions, retrieval-only mole, and the Conversations view — design

**Date:** 2026-08-27 · **Status:** approved direction, pending final spec review
**Prototype:** `docs/superpowers/prototypes/2026-08-27-chat-workspace.html`
(deep-linkable: `#view=chats`, `#focus=claude`, `#mode=floating`)

## Problem

Ask Stash appends every message to a single `conversations` row forever. The
thread grows unboundedly (Will's is already 200+ messages), old topics pollute
nothing today only because the server caps history at 10 turns, and there is no
way to find or revisit an earlier exchange. Separately, the mole doubles as a
capture surface (URL → `add-url`, `remember:` → `add-note`), which muddies its
purpose now that capture has many better surfaces.

## Decisions (settled with Will, 2026-08-27)

1. **Auto-sessions by time gap; zero decisions.** A conversation = a burst of
   activity. New session after **3 hours** of inactivity. Nothing to name,
   file, or manage. No day-boundary rule.
2. **Mole stays as-is in footprint** (floating pill ⌘K → pinned 384px dock).
   No three-column workspace, no new route.
3. **Mole becomes retrieval-only.** Capture routing (`classifyMoleMessage`) is
   removed from the mole; every message goes to chat.
4. **"Earlier conversations" link** replaces the sources hint at the bottom of
   the mole. Clicking swaps the main pane (card grid area) to a
   **Conversations** list; the link toggles to "Back to your stash".
5. **Conversations list** is bucketed Today / Yesterday / This week / Month
   Year / Earlier, newest first. Each row: auto-title, one-line preview of the
   last assistant message, time, message count. Clicking a row **loads that
   session into the mole** (surfacing/pinning it if minimized); typing resumes
   it. A session selected this way is exempt from the 3-hour rule — explicit
   selection wins.
6. **Focus sources stays.** Answers with sources get a "⌖ Focus sources (n)"
   chip that filters the main card grid to the cited items (source order) with
   a "Showing n cards from this answer · Clear" pill. Focusing always switches
   the main pane back to cards (focus is a request to see items; the
   conversations list yields).
7. **No backfill.** The existing mega-conversation stays one row; it appears
   under "Earlier" naturally. Sessions apply going forward.

## Data model

One migration:

```sql
ALTER TABLE conversations ADD COLUMN last_message_at timestamptz;
-- backfill from each conversation's newest message; default now() on insert
CREATE INDEX ON conversations (user_id, last_message_at DESC);
-- trigger: AFTER INSERT ON messages → UPDATE parent conversation
--   SET last_message_at = NEW.created_at
```

The trigger (not client writes) keeps ordering correct regardless of which
client persists a message. No other schema changes; `messages` and
`messages.source_items` are unchanged.

## Session resolution (client)

Pure util `src/utils/chatSessions.ts`:

- `resolveSessionTarget(latest: {id, last_message_at} | null, now: Date) →
  {kind: 'continue', id} | {kind: 'new'}` — continue iff
  `now − last_message_at < 3h`.
- `bucketConversations(rows, now)` — groups into Today / Yesterday / This
  week / `MMMM yyyy` / Earlier for the list view.

ChatMole flow changes:

- On first expand: fetch the **latest** conversation (order by
  `last_message_at desc limit 1`) instead of the oldest; apply
  `resolveSessionTarget`. If 'new', show an empty thread; the conversation row
  is created lazily on the first send (avoids empty-session rows).
- On send: re-check the gap (a pinned-open mole left overnight must not append
  to yesterday's session). If the gap elapsed since the last message, create a
  new conversation first.
- `conversationHistory` sent to the server = current session's messages only.
  (Server keeps its 10-turn cap; no server changes.)
- An explicitly selected (resumed) session skips gap checks until the mole is
  next collapsed/reloaded — explicit selection wins.

## Auto-titles

After the first assistant reply lands in a session with `title IS NULL` (new
sessions insert with null title), the client fires the existing
`generate-title` edge function with the first user question and PATCHes
`conversations.title`. Display fallback while null: truncated first question,
or "New chat" before any message. The legacy conversation keeps its "Ask
Stash" title.

## Mole changes

- Remove `classifyMoleMessage` routing from ChatMole (util + tests stay for
  other surfaces if any; if the mole was the only consumer, delete
  `moleRouting.ts` and its tests). Composer placeholder → "Ask your stash…".
- Footer hint replaced by the "Earlier conversations" toggle link.
- Thread header shows the session title (auto-title once generated).
- History load: latest session's messages only (not 60 messages across all
  time).

## Conversations view (main pane)

- New component `ConversationsView` rendered by `Index.tsx` in place of
  `ContentGrid` when `view === 'chats'` (plain state, not a route; toolbar and
  capture panel stay visible and functional).
- Data: a small RPC `list_conversations()` added in the same migration —
  `SECURITY INVOKER` (runs under the caller's JWT; existing owner-scoped RLS
  on `conversations`/`messages` applies), returning
  `(id, title, last_message_at, message_count, preview)` where `preview` is
  the last assistant message's first ~140 chars. One round-trip, no N+1.
- Row click → `onOpenConversation(id)`: sets the mole's active session
  (pinning/surfacing the mole if minimized), loads its messages.
- "← Back to your stash" link and the mole's toggled footer link both return
  to cards.

## Focus sources

- `MoleMessage.sources` already carries ids (live) and `messages.source_items`
  persists them (reload). Chip renders when ids exist.
- Chip click → `Index` state `focusItemIds: string[] | null`; `ContentGrid`
  reuses the id-filter path built for server search (filter + source order —
  same mechanism as `serverResultIds`, kept as a separate prop so search and
  focus don't fight; focus wins while active).
- Pill "Showing n cards from this answer · Clear"; Clear (or toggling the chip
  off, or starting a new search) restores the grid. Focusing sets
  `view = 'cards'`.

## Cross-platform contract (ui-changes.md entry ships with the branch)

- Sessions are a **client convention** on existing tables: pick-or-create by
  the 3-hour rule against `last_message_at`; send only the current session as
  `conversationHistory`. iOS/mac inherit sessions by following the same
  convention. The trigger keeps `last_message_at` true for any client.
- Mole routing removal is a **product decision for all platforms**: chat
  composers are retrieval-only; capture belongs to capture surfaces. Web
  deletes `moleRouting.ts` (+tests). iOS currently implements the convention
  (`StashKit/MessageRouting.swift`, used by `AskView`/`ChatComposerBar`) and
  should mirror the removal — the `ui-changes.md` entry says so explicitly.
  `PLATFORM_API.md`'s "Message routing convention" section is replaced with a
  retirement note (dated) so no new client builds on it.

## Testing

- Unit: `resolveSessionTarget` (boundary at exactly 3h, null latest, null
  `last_message_at`), `bucketConversations` (bucket edges: midnight, week
  start, year rollover), focus-filter precedence over server-search filter.
- Component: ChatMole new-session-on-send behavior with a mocked clock;
  ConversationsView row → open-session wiring.
- Manual (prototype parity): floating→pinned, earlier-conversations toggle,
  resume-and-type, focus/clear, new-session after gap.

## Out of scope (v1)

History search; topic clustering; retroactive splitting of the legacy
conversation; mobile-specific conversations UI; SMS path; iOS implementation
(contract only); deleting/renaming conversations; persisting `status` frames.
