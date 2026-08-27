# Chat Sessions + Retrieval-Only Mole Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Segment Ask Stash into auto-sessions (3-hour gap), make the mole retrieval-only, add a Conversations view on the main page, and let answers focus their cited cards in the grid.

**Architecture:** Sessions are a client convention over the existing `conversations`/`messages` tables — one migration adds `last_message_at` (+trigger) and a `list_conversations()` RPC; everything else is web-client work in ChatMole, a new ConversationsView, and Index wiring. No edge-function changes.

**Tech Stack:** Vite + React + TS, Supabase (Postgres RLS, PostgREST RPC), vitest + @testing-library/react, date-fns.

**Spec:** `docs/superpowers/specs/2026-08-27-chat-sessions-design.md`

## Global Constraints

- The working tree contains unrelated uncommitted changes (retrieval overhaul phases 1–3). `git add` ONLY the exact files named in your task — never `git add -A` or `git add .`.
- Session gap is exactly **3 hours** (`SESSION_GAP_MS = 3 * 60 * 60 * 1000`); gap elapsed at exactly 3h means NEW session.
- Migrations are applied to prod via the Supabase Management API (CLI is not DB-linked): token from macOS keychain `security find-generic-password -s "Supabase CLI" -a "supabase" -w`, strip `go-keyring-base64:` prefix, base64-decode. Project ref `uqqsgmwkvslaomzxptnp`. Record every applied migration in `supabase_migrations.schema_migrations`.
- Tests: `npm test` (vitest, non-interactive). Typecheck: `npx tsc --noEmit -p tsconfig.app.json` (`vite build` does NOT typecheck).
- Copy rules (Will-approved): footer link reads **"Earlier conversations"** / toggled **"Back to your stash"**; focus chip reads **"⌖ Focus sources (n)"**; pill reads **"Showing n cards from this answer"** with a **"Clear"** button; composer placeholder reads **"Ask your stash…"**.
- Per repo convention, large components (ChatMole) have no component tests — behavior is covered by pure-util unit tests plus the Task 9 manual checklist. ConversationsView is new and small: it DOES get a component test.

---

### Task 1: Migration — sessions infrastructure

**Files:**
- Create: `supabase/migrations/20260827120000_chat_sessions.sql`
- Modify: `src/integrations/supabase/types.ts` (regenerated, not hand-edited)

**Interfaces:**
- Consumes: existing `conversations(id, user_id, title, created_at, updated_at)` and `messages(conversation_id, role, content, source_items, created_at)`.
- Produces: `conversations.last_message_at timestamptz` (default `now()`, trigger-maintained); RPC `list_conversations() → (id uuid, title text, last_message_at timestamptz, message_count bigint, preview text)`, SECURITY INVOKER (RLS-scoped, callable with the user's JWT).

- [ ] **Step 1: Write the migration file**

`supabase/migrations/20260827120000_chat_sessions.sql`:

```sql
-- Chat sessions (spec: docs/superpowers/specs/2026-08-27-chat-sessions-design.md).
-- Conversations become time-gap sessions — a client convention; the DB only
-- guarantees last_message_at is true (trigger) and serves the list RPC.

ALTER TABLE public.conversations ADD COLUMN IF NOT EXISTS last_message_at timestamptz;

UPDATE public.conversations c
  SET last_message_at = COALESCE(
    (SELECT max(m.created_at) FROM public.messages m WHERE m.conversation_id = c.id),
    c.created_at)
  WHERE c.last_message_at IS NULL;

ALTER TABLE public.conversations ALTER COLUMN last_message_at SET DEFAULT now();
-- New sessions are created with title NULL and auto-titled after the first
-- exchange; make sure the column allows it (no-op if already nullable).
ALTER TABLE public.conversations ALTER COLUMN title DROP NOT NULL;

CREATE INDEX IF NOT EXISTS idx_conversations_user_last
  ON public.conversations (user_id, last_message_at DESC);

-- The trigger (not client writes) keeps ordering correct no matter which
-- client persists a message. SECURITY DEFINER so the owner-bypass covers the
-- parent-row update; the row being touched was already RLS-validated by the
-- message INSERT.
CREATE OR REPLACE FUNCTION public.touch_conversation_last_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.conversations
    SET last_message_at = NEW.created_at
    WHERE id = NEW.conversation_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_messages_touch_conversation ON public.messages;
CREATE TRIGGER trg_messages_touch_conversation
  AFTER INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.touch_conversation_last_message();

-- Conversations list: one round-trip for the view. SECURITY INVOKER — runs
-- under the caller's JWT, so the owner-scoped RLS on conversations/messages
-- does the tenant scoping (deliberately unlike hybrid_search_content).
CREATE OR REPLACE FUNCTION public.list_conversations()
RETURNS TABLE (
  id uuid,
  title text,
  last_message_at timestamptz,
  message_count bigint,
  preview text
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT c.id, c.title, c.last_message_at,
         (SELECT count(*) FROM messages m WHERE m.conversation_id = c.id) AS message_count,
         (SELECT left(m.content, 140) FROM messages m
            WHERE m.conversation_id = c.id AND m.role = 'assistant'
            ORDER BY m.created_at DESC LIMIT 1) AS preview
  FROM conversations c
  WHERE c.user_id = auth.uid()
  ORDER BY c.last_message_at DESC NULLS LAST
$$;
```

- [ ] **Step 2: Apply to prod via the Management API**

```bash
TOKEN=$(security find-generic-password -s "Supabase CLI" -a "supabase" -w | sed 's/^go-keyring-base64://' | base64 -d)
jq -n --rawfile q supabase/migrations/20260827120000_chat_sessions.sql '{query:$q}' \
  | curl -s -X POST "https://api.supabase.com/v1/projects/uqqsgmwkvslaomzxptnp/database/query" \
      -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d @-
```

Expected: `[]`. Any `{"message":"Failed to run sql query…"}` is a failure — stop and fix.

- [ ] **Step 3: Record the migration**

Same curl pattern with:

```sql
INSERT INTO supabase_migrations.schema_migrations (version, name)
VALUES ('20260827120000','chat_sessions') ON CONFLICT DO NOTHING;
```

- [ ] **Step 4: Verify live**

Same curl pattern with:

```sql
SELECT
  (SELECT count(*) FROM public.conversations WHERE last_message_at IS NULL) AS null_lma,
  (SELECT count(*) FROM pg_trigger WHERE tgname = 'trg_messages_touch_conversation') AS trigger_ok,
  (SELECT count(*) FROM pg_proc WHERE proname = 'list_conversations') AS rpc_ok;
```

Expected: `[{"null_lma":0,"trigger_ok":1,"rpc_ok":1}]`.

- [ ] **Step 5: Regenerate types and typecheck**

```bash
supabase gen types typescript --project-id uqqsgmwkvslaomzxptnp --schema public > /tmp/types.ts \
  && grep -q "list_conversations" /tmp/types.ts \
  && cp /tmp/types.ts src/integrations/supabase/types.ts
npx tsc --noEmit -p tsconfig.app.json
```

Expected: grep succeeds; tsc exits 0.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260827120000_chat_sessions.sql src/integrations/supabase/types.ts
git commit -m "feat(chat): sessions migration — last_message_at + trigger + list_conversations RPC"
```

---

### Task 2: Session utils (`chatSessions.ts`)

**Files:**
- Create: `src/utils/chatSessions.ts`
- Test: `src/utils/chatSessions.test.ts`

**Interfaces:**
- Produces (later tasks import these exact names):

```ts
export const SESSION_GAP_MS: number; // 3h
export interface SessionCandidate { id: string; title: string | null; last_message_at: string | null; }
export function resolveSessionTarget(latest: SessionCandidate | null, now: Date):
  { kind: 'continue'; id: string; title: string | null } | { kind: 'new' };
export interface ConversationListRow { id: string; title: string | null; last_message_at: string; message_count: number; preview: string | null; }
export interface ConversationBucket { label: string; rows: ConversationListRow[]; }
export function bucketConversations(rows: ConversationListRow[], now: Date): ConversationBucket[];
```

- [ ] **Step 1: Write the failing tests**

`src/utils/chatSessions.test.ts`:

```ts
import { resolveSessionTarget, bucketConversations, SESSION_GAP_MS } from './chatSessions';

const NOW = new Date('2026-08-27T15:00:00Z');
const iso = (msAgo: number) => new Date(NOW.getTime() - msAgo).toISOString();
const row = (id: string, msAgo: number) => ({
  id, title: id, last_message_at: iso(msAgo), message_count: 2, preview: null,
});

describe('resolveSessionTarget', () => {
  it('starts new with no prior conversation', () => {
    expect(resolveSessionTarget(null, NOW)).toEqual({ kind: 'new' });
  });

  it('continues within the gap', () => {
    expect(
      resolveSessionTarget({ id: 'c1', title: 'T', last_message_at: iso(SESSION_GAP_MS - 60_000) }, NOW)
    ).toEqual({ kind: 'continue', id: 'c1', title: 'T' });
  });

  it('starts new at exactly the gap boundary', () => {
    expect(
      resolveSessionTarget({ id: 'c1', title: 'T', last_message_at: iso(SESSION_GAP_MS) }, NOW)
    ).toEqual({ kind: 'new' });
  });

  it('starts new when last_message_at is null', () => {
    expect(
      resolveSessionTarget({ id: 'c1', title: 'T', last_message_at: null }, NOW)
    ).toEqual({ kind: 'new' });
  });
});

describe('bucketConversations', () => {
  it('buckets Today / Yesterday / This week / month / older year', () => {
    const rows = [
      row('today', 60 * 60 * 1000),                 // Thu Aug 27
      row('yesterday', 26 * 60 * 60 * 1000),        // Wed Aug 26
      row('thisweek', 3 * 24 * 60 * 60 * 1000),     // Mon Aug 24 (same ISO week)
      row('july', 40 * 24 * 60 * 60 * 1000),        // Jul 18
      row('lastyear', 400 * 24 * 60 * 60 * 1000),   // Jul 2025
    ];
    const buckets = bucketConversations(rows, NOW);
    expect(buckets.map(b => b.label)).toEqual(['Today', 'Yesterday', 'This week', 'July', 'July 2025']);
    expect(buckets[0].rows[0].id).toBe('today');
  });

  it('groups multiple rows under one bucket, preserving order', () => {
    const rows = [row('a', 1000), row('b', 2000)];
    const buckets = bucketConversations(rows, NOW);
    expect(buckets).toHaveLength(1);
    expect(buckets[0].rows.map(r => r.id)).toEqual(['a', 'b']);
  });

  it('returns empty for no rows', () => {
    expect(bucketConversations([], NOW)).toEqual([]);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npx vitest run src/utils/chatSessions.test.ts`
Expected: FAIL — cannot resolve `./chatSessions`.

- [ ] **Step 3: Implement**

`src/utils/chatSessions.ts`:

```ts
import { differenceInCalendarDays, format, isSameWeek } from 'date-fns';

// A conversation is a burst of activity: 3+ hours of silence starts a new one.
export const SESSION_GAP_MS = 3 * 60 * 60 * 1000;

export interface SessionCandidate {
  id: string;
  title: string | null;
  last_message_at: string | null;
}

export function resolveSessionTarget(
  latest: SessionCandidate | null,
  now: Date
): { kind: 'continue'; id: string; title: string | null } | { kind: 'new' } {
  if (!latest?.last_message_at) return { kind: 'new' };
  const elapsed = now.getTime() - new Date(latest.last_message_at).getTime();
  return elapsed < SESSION_GAP_MS
    ? { kind: 'continue', id: latest.id, title: latest.title }
    : { kind: 'new' };
}

export interface ConversationListRow {
  id: string;
  title: string | null;
  last_message_at: string;
  message_count: number;
  preview: string | null;
}

export interface ConversationBucket {
  label: string;
  rows: ConversationListRow[];
}

// Rows arrive newest-first (list_conversations orders by last_message_at desc),
// so buckets emit in display order with one pass.
export function bucketConversations(
  rows: ConversationListRow[],
  now: Date
): ConversationBucket[] {
  const buckets: ConversationBucket[] = [];
  for (const r of rows) {
    const d = new Date(r.last_message_at);
    const days = differenceInCalendarDays(now, d);
    let label: string;
    if (days <= 0) label = 'Today';
    else if (days === 1) label = 'Yesterday';
    else if (isSameWeek(d, now, { weekStartsOn: 1 })) label = 'This week';
    else label = d.getFullYear() === now.getFullYear() ? format(d, 'MMMM') : format(d, 'MMMM yyyy');
    const last = buckets[buckets.length - 1];
    if (last && last.label === label) last.rows.push(r);
    else buckets.push({ label, rows: [r] });
  }
  return buckets;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npx vitest run src/utils/chatSessions.test.ts`
Expected: PASS (7 tests). If the "thisweek" fixture crosses an ISO-week boundary, adjust the fixture (not the code) — the rule is `isSameWeek` with Monday start.

- [ ] **Step 5: Commit**

```bash
git add src/utils/chatSessions.ts src/utils/chatSessions.test.ts
git commit -m "feat(chat): session-gap resolution and date bucketing utils"
```

---

### Task 3: ChatMole session lifecycle

**Files:**
- Modify: `src/components/ChatMole.tsx` (history load ~lines 74–120, `persistMessage` ~121–140, `ask()`/`handleSend` ~230–330)

**Interfaces:**
- Consumes: `resolveSessionTarget`, `SESSION_GAP_MS`, `SessionCandidate` from `@/utils/chatSessions` (Task 2).
- Produces: new ChatMole props (Index wires them in Task 7):

```ts
interface ChatMoleProps {
  pinned: boolean;
  onPinnedChange: (pinned: boolean) => void;
  onSourceClick?: (sourceId: string) => void;
  itemCount: number;
  // Task 3:
  openConversationRequest?: { id: string; title: string | null; token: number } | null;
  // Task 5 adds: conversationsOpen, onToggleConversations, focusedSourceIds, onFocusSources
}
```

Also produces internal state later tasks touch: `sessionRef` (`{ id: string | null; lastMessageAt: number; explicit: boolean }`), `sessionTitle` state + `sessionTitleRef`, and `MoleMessage.sourceItemIds?: string[]`.

- [ ] **Step 1: Replace the history loader**

In `ChatMole.tsx`, add imports and session state near the other refs:

```ts
import { resolveSessionTarget, SESSION_GAP_MS } from '@/utils/chatSessions';
```

```ts
const sessionRef = useRef<{ id: string | null; lastMessageAt: number; explicit: boolean }>(
  { id: null, lastMessageAt: 0, explicit: false }
);
const [sessionTitle, setSessionTitle] = useState<string | null>(null);
const sessionTitleRef = useRef<string | null>(null);
sessionTitleRef.current = sessionTitle;
```

Add `sourceItemIds?: string[]` to the `MoleMessage` interface (used by focus chips in Task 5).

Replace the body of `loadHistory` (currently: pick OLDEST conversation, create "Ask Stash" if missing, load latest 60 messages). New behavior — pick the LATEST session and apply the gap rule; never create a row here (rows are created lazily on first send):

```ts
const loadHistory = async () => {
  try {
    const { data: latest } = await supabase
      .from('conversations')
      .select('id, title, last_message_at')
      .eq('user_id', user.id)
      .order('last_message_at', { ascending: false, nullsFirst: false })
      .limit(1)
      .maybeSingle();

    const target = resolveSessionTarget(latest ?? null, new Date());
    if (target.kind === 'new') {
      // Fresh thread; the conversation row is created on first send
      sessionRef.current = { id: null, lastMessageAt: 0, explicit: false };
      return;
    }

    sessionRef.current = {
      id: target.id,
      lastMessageAt: new Date(latest!.last_message_at!).getTime(),
      explicit: false,
    };
    setSessionTitle(target.title);
    await loadConversationMessages(target.id);
  } catch (error) {
    console.error('Failed to load chat history (non-fatal):', error);
  }
};
```

Extract the message fetch into a reusable helper (the open-conversation effect below uses it too). Note it now restores `source_items` so focus chips work on reloaded history:

```ts
const loadConversationMessages = async (conversationId: string) => {
  const { data: history } = await supabase
    .from('messages')
    .select('id, role, content, source_items, created_at')
    .eq('conversation_id', conversationId)
    .order('created_at', { ascending: true })
    .limit(200);
  const restored: MoleMessage[] = (history ?? [])
    .filter(m => m.role === 'user' || m.role === 'assistant')
    .map(m => ({
      id: m.id,
      role: m.role as 'user' | 'assistant',
      content: m.content,
      sourceItemIds: m.source_items ?? undefined,
    }));
  setMessages(restored);
};
```

Delete the old "find oldest / insert `title: 'Ask Stash'`" block and `conversationIdRef` (replaced by `sessionRef`; update `persistMessage` to read `sessionRef.current.id`). After a successful insert in `persistMessage`, add `sessionRef.current.lastMessageAt = Date.now();`.

- [ ] **Step 2: Lazy session creation + gap re-check on send**

Add above `ask()`:

```ts
const createConversation = async (): Promise<string | null> => {
  if (!user?.id) return null;
  const { data, error } = await supabase
    .from('conversations')
    .insert({ user_id: user.id, title: null })
    .select('id')
    .single();
  if (error) {
    console.error('Failed to create conversation (non-fatal):', error);
    return null;
  }
  return data.id;
};

// Returns the conversation id to persist into, creating a new session when
// the 3h gap elapsed. Explicitly resumed sessions are exempt from the gap.
const ensureSessionForSend = async (): Promise<string | null> => {
  const s = sessionRef.current;
  const now = Date.now();
  if (s.id && (s.explicit || now - s.lastMessageAt < SESSION_GAP_MS)) return s.id;
  if (s.id) setMessages([]); // stale session on screen — new session starts a fresh thread
  const id = await createConversation();
  sessionRef.current = { id, lastMessageAt: now, explicit: false };
  setSessionTitle(null);
  return id;
};
```

At the top of `ask(question)` (before `pushMessage(userMessage)`), insert:

```ts
await ensureSessionForSend();
```

(`persistMessage` keeps its `if (!conversationId) return` guard — if creation failed, chat still works unpersisted, matching the existing non-fatal philosophy.)

- [ ] **Step 3: Open-conversation requests (from the Conversations view)**

Add the prop and effect (token forces re-fire even for the same id):

```ts
useEffect(() => {
  const req = openConversationRequest;
  if (!req) return;
  sessionRef.current = { id: req.id, lastMessageAt: Date.now(), explicit: true };
  setSessionTitle(req.title);
  void loadConversationMessages(req.id);
}, [openConversationRequest?.token]);
```

Also update the expanded header (line ~379): replace the static `Ask Stash` title with `{sessionTitle ?? 'Ask Stash'}`, and change the subtitle (line ~381) from `Answers from your {itemCount} items · paste links here to save them` to `Answers from your {itemCount} items`.

- [ ] **Step 4: Typecheck and run the suite**

Run: `npx tsc --noEmit -p tsconfig.app.json && npm test`
Expected: tsc clean; all tests pass (Index doesn't pass the new optional prop yet — that's fine, it's optional).

- [ ] **Step 5: Commit**

```bash
git add src/components/ChatMole.tsx
git commit -m "feat(chat): mole targets latest session, 3h-gap rule, lazy creation, explicit resume"
```

---

### Task 4: Auto-titles

**Files:**
- Modify: `src/components/ChatMole.tsx` (the `payload.done` handler inside `ask()`)

**Interfaces:**
- Consumes: `sessionRef`, `sessionTitle`/`sessionTitleRef` (Task 3); edge function `generate-title` — request `{ content: string }`, response `{ title: string }` (returns `{ title: 'Untitled Note' }` on internal failure).

- [ ] **Step 1: Fire-and-forget title generation after the first exchange**

In the `payload.done` branch (after `persistMessage('assistant', baked, …)`), add:

```ts
if (!sessionTitleRef.current && sessionRef.current.id) {
  const conversationId = sessionRef.current.id;
  void supabase.functions
    .invoke('generate-title', { body: { content: question } })
    .then(async ({ data }) => {
      const title = (data?.title || question).trim().slice(0, 80);
      setSessionTitle(title);
      await supabase.from('conversations').update({ title }).eq('id', conversationId);
    })
    .catch((e: unknown) => console.error('Title generation failed (non-fatal):', e));
}
```

(`question` is already in scope in `ask()`. The legacy "Ask Stash" conversation has a non-null title, so it is never retitled.)

- [ ] **Step 2: Typecheck and run the suite**

Run: `npx tsc --noEmit -p tsconfig.app.json && npm test`
Expected: clean/green.

- [ ] **Step 3: Commit**

```bash
git add src/components/ChatMole.tsx
git commit -m "feat(chat): auto-title sessions after first exchange"
```

---

### Task 5: Retrieval-only mole + footer link + focus chips

**Files:**
- Modify: `src/components/ChatMole.tsx`
- Delete: `src/utils/moleRouting.ts`, `src/utils/moleRouting.test.ts`

**Interfaces:**
- Produces ChatMole props (wired by Index in Task 7):

```ts
conversationsOpen?: boolean;                       // default false
onToggleConversations?: () => void;
focusedSourceIds?: string[] | null;                // currently focused ids (for chip active state)
onFocusSources?: (ids: string[] | null) => void;   // null = clear
```

- [ ] **Step 1: Remove capture routing**

In `ChatMole.tsx`:
- Delete the `classifyMoleMessage` import.
- Simplify `handleSend` — the `try` block becomes just `await ask(text);` (delete the `route` branching).
- Delete the now-unused `saveUrl` and `saveNote` functions, the `savedItem` field on `MoleMessage`, the `'saved'` role from its union, and the `message.role === 'saved'` render branch (~lines 407–417).
- Delete the `canAddContent` usage if it was only consumed by the save paths (keep `canUseAI`).
- Change the composer `placeholder` to `Ask your stash…`.

Then delete the routing util:

```bash
git rm src/utils/moleRouting.ts src/utils/moleRouting.test.ts
```

Run `grep -rn "moleRouting\|classifyMoleMessage" src/` — expected: no matches.

- [ ] **Step 2: Replace the footer hint with the Earlier-conversations link**

Replace (line ~570):

```tsx
<div className="mt-2 text-[11.5px] text-muted-foreground">
  Answers come with sources · <b>links pasted here are saved</b> · <b>remember:</b> saves a note
</div>
```

with:

```tsx
<div className="mt-2 text-[11.5px]">
  <button
    onClick={onToggleConversations}
    className={
      conversationsOpen
        ? 'font-medium text-violet-700 hover:underline underline-offset-2'
        : 'text-muted-foreground hover:text-violet-700 hover:underline underline-offset-2'
    }
  >
    {conversationsOpen ? 'Back to your stash' : 'Earlier conversations'}
  </button>
</div>
```

- [ ] **Step 3: Add focus chips to assistant messages**

In the assistant render branch, the message's focusable ids are
`const focusIds = message.sources?.map(s => s.id) ?? message.sourceItemIds ?? [];`
Below the read-aloud button (same `msg-tools` row area), when `focusIds.length > 0 && onFocusSources`:

```tsx
{focusIds.length > 0 && onFocusSources && (
  <button
    onClick={() => {
      const isActive =
        focusedSourceIds?.length === focusIds.length &&
        focusIds.every(id => focusedSourceIds.includes(id));
      onFocusSources(isActive ? null : focusIds);
    }}
    className={`inline-flex items-center gap-1 rounded-full border px-2.5 py-0.5 text-[11.5px] ${
      focusedSourceIds && focusIds.every(id => focusedSourceIds.includes(id)) && focusedSourceIds.length === focusIds.length
        ? 'border-violet-600 bg-violet-600 text-white'
        : 'border-violet-200 bg-white text-violet-700 hover:bg-violet-50'
    }`}
  >
    ⌖ Focus sources ({focusIds.length})
  </button>
)}
```

- [ ] **Step 4: Typecheck and run the suite**

Run: `npx tsc --noEmit -p tsconfig.app.json && npm test`
Expected: clean; the moleRouting test file is gone so the count drops accordingly; nothing else fails.

- [ ] **Step 5: Commit**

```bash
git add src/components/ChatMole.tsx
git commit -m "feat(chat): retrieval-only mole — routing removed, Earlier-conversations link, focus chips"
```

(The `git rm` from Step 1 is already staged.)

---

### Task 6: ConversationsView component

**Files:**
- Create: `src/components/ConversationsView.tsx`
- Test: `src/components/ConversationsView.test.tsx`

**Interfaces:**
- Consumes: `bucketConversations`, `ConversationListRow` (Task 2); RPC `list_conversations` (Task 1).
- Produces:

```ts
interface ConversationsViewProps {
  onOpenConversation: (c: { id: string; title: string | null }) => void;
  onBack: () => void;
}
export default ConversationsView;
```

- [ ] **Step 1: Write the failing component test**

`src/components/ConversationsView.test.tsx`:

```tsx
import { render, screen, waitFor, fireEvent } from '@testing-library/react';
import ConversationsView from './ConversationsView';

const { mockRpc } = vi.hoisted(() => ({ mockRpc: vi.fn() }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc: mockRpc } }));

const rows = [
  { id: 'c1', title: 'Claude automation', last_message_at: new Date().toISOString(), message_count: 6, preview: 'Beyond the basics…' },
  { id: 'c2', title: null, last_message_at: new Date().toISOString(), message_count: 2, preview: null },
];

describe('ConversationsView', () => {
  beforeEach(() => vi.clearAllMocks());

  it('lists conversations from the RPC in buckets and opens on click', async () => {
    mockRpc.mockResolvedValue({ data: rows, error: null });
    const onOpen = vi.fn();
    render(<ConversationsView onOpenConversation={onOpen} onBack={() => {}} />);

    await waitFor(() => expect(screen.getByText('Claude automation')).toBeTruthy());
    expect(mockRpc).toHaveBeenCalledWith('list_conversations');
    expect(screen.getByText('Today')).toBeTruthy();
    expect(screen.getByText('New chat')).toBeTruthy(); // null-title fallback

    fireEvent.click(screen.getByText('Claude automation'));
    expect(onOpen).toHaveBeenCalledWith({ id: 'c1', title: 'Claude automation' });
  });

  it('shows the empty state and back link', async () => {
    mockRpc.mockResolvedValue({ data: [], error: null });
    const onBack = vi.fn();
    render(<ConversationsView onOpenConversation={() => {}} onBack={onBack} />);

    await waitFor(() => expect(screen.getByText(/No conversations yet/i)).toBeTruthy());
    fireEvent.click(screen.getByText('← Back to your stash'));
    expect(onBack).toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `npx vitest run src/components/ConversationsView.test.tsx`
Expected: FAIL — cannot resolve `./ConversationsView`.

- [ ] **Step 3: Implement the component**

`src/components/ConversationsView.tsx`:

```tsx
import { useEffect, useState } from 'react';
import { format } from 'date-fns';
import { supabase } from '@/integrations/supabase/client';
import { bucketConversations, type ConversationListRow } from '@/utils/chatSessions';

interface ConversationsViewProps {
  onOpenConversation: (c: { id: string; title: string | null }) => void;
  onBack: () => void;
}

// Main-pane replacement for the card grid while "Earlier conversations" is
// open. Read-only list; clicking a row loads that session into the mole.
const ConversationsView = ({ onOpenConversation, onBack }: ConversationsViewProps) => {
  const [rows, setRows] = useState<ConversationListRow[] | null>(null);

  useEffect(() => {
    let cancelled = false;
    void supabase.rpc('list_conversations').then(({ data, error }) => {
      if (cancelled) return;
      if (error) {
        console.error('list_conversations failed:', error);
        setRows([]);
        return;
      }
      setRows((data ?? []) as ConversationListRow[]);
    });
    return () => { cancelled = true; };
  }, []);

  const buckets = rows ? bucketConversations(rows, new Date()) : [];

  return (
    <div className="mx-auto max-w-3xl">
      <button
        onClick={onBack}
        className="mb-4 text-sm text-muted-foreground hover:text-foreground"
      >
        ← Back to your stash
      </button>
      <h1 className="text-lg font-semibold">Conversations</h1>
      <p className="mb-4 text-sm text-muted-foreground">
        Chats start fresh after a few hours away — nothing to name or file.
      </p>

      {rows && rows.length === 0 && (
        <p className="py-10 text-center text-sm text-muted-foreground">
          No conversations yet — ask your stash something.
        </p>
      )}

      {buckets.map(bucket => (
        <section key={bucket.label}>
          <h2 className="pb-2 pt-5 text-[10.5px] font-semibold uppercase tracking-wider text-muted-foreground">
            {bucket.label}
          </h2>
          {bucket.rows.map(row => (
            <button
              key={row.id}
              onClick={() => onOpenConversation({ id: row.id, title: row.title })}
              className="mb-2 flex w-full items-center gap-3 rounded-xl border border-border bg-white px-4 py-3 text-left transition hover:shadow-md"
            >
              <span className="h-2 w-2 flex-none rounded-full bg-violet-300" />
              <span className="min-w-0 flex-1">
                <span className="block truncate text-sm font-medium">
                  {row.title ?? 'New chat'}
                </span>
                {row.preview && (
                  <span className="block truncate text-xs text-muted-foreground">
                    {row.preview}
                  </span>
                )}
              </span>
              <span className="flex-none text-right text-xs leading-relaxed text-muted-foreground">
                {format(new Date(row.last_message_at), 'MMM d')}
                <br />
                {row.message_count} message{row.message_count === 1 ? '' : 's'}
              </span>
            </button>
          ))}
        </section>
      ))}
    </div>
  );
};

export default ConversationsView;
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `npx vitest run src/components/ConversationsView.test.tsx`
Expected: PASS (2 tests). If `supabase.rpc('list_conversations')` types complain before Task 1's regenerated types are present, cast: `supabase.rpc('list_conversations' as never)` is NOT allowed — Task 1 runs first; fix ordering instead.

- [ ] **Step 5: Commit**

```bash
git add src/components/ConversationsView.tsx src/components/ConversationsView.test.tsx
git commit -m "feat(chat): ConversationsView — bucketed session list on the main page"
```

---

### Task 7: Index wiring — view state, focus state, grid focus filter

**Files:**
- Modify: `src/pages/Index.tsx` (state ~lines 47–58, ChatMole render, main pane render ~150–160)
- Modify: `src/components/ContentGrid.tsx` (props + the filter block that already handles `serverResultIds`)

**Interfaces:**
- Consumes: `ConversationsView` (Task 6); ChatMole props from Tasks 3/5.
- Produces: `ContentGrid` prop `focusItemIds?: string[] | null` — when non-null it takes precedence over BOTH `serverResultIds` and the client substring filter (tag/type filters still intersect).

- [ ] **Step 1: Index state + ChatMole/main-pane wiring**

In `Index.tsx` add imports and state:

```ts
import ConversationsView from '@/components/ConversationsView';
```

```ts
const [mainView, setMainView] = useState<'cards' | 'chats'>('cards');
const [focusItemIds, setFocusItemIds] = useState<string[] | null>(null);
const [openConvoReq, setOpenConvoReq] = useState<{ id: string; title: string | null; token: number } | null>(null);
```

Handlers:

```ts
const handleFocusSources = (ids: string[] | null) => {
  setFocusItemIds(ids);
  if (ids) setMainView('cards'); // focusing is a request to SEE items — the list yields
};

const handleOpenConversation = (c: { id: string; title: string | null }) => {
  setOpenConvoReq({ ...c, token: Date.now() });
  handleMolePinnedChange(true); // surface the mole if minimized
};
```

Replace the `<main>` contents: when `mainView === 'chats'` render
`<ConversationsView onOpenConversation={handleOpenConversation} onBack={() => setMainView('cards')} />`
instead of `<ContentGrid …/>`; the toolbar render condition gains `&& mainView === 'cards'`. ContentGrid gains `focusItemIds={focusItemIds}`.

Above the grid (inside `<main>`, cards view only), render the focus pill when `focusItemIds`:

```tsx
{mainView === 'cards' && focusItemIds && (
  <div className="mb-3 inline-flex items-center gap-2 rounded-full bg-violet-100 py-1 pl-3 pr-1.5 text-xs text-violet-700">
    <span>Showing <b>{focusItemIds.length}</b> cards from this answer</span>
    <button
      onClick={() => setFocusItemIds(null)}
      className="rounded-full bg-white px-2.5 py-0.5 text-[11.5px]"
    >
      Clear
    </button>
  </div>
)}
```

Wire ChatMole (find its render; it already receives `pinned`, `onPinnedChange`, `onSourceClick`, `itemCount`):

```tsx
<ChatMole
  pinned={molePinned}
  onPinnedChange={handleMolePinnedChange}
  onSourceClick={handleSourceClick}
  itemCount={realItemCount}
  conversationsOpen={mainView === 'chats'}
  onToggleConversations={() => setMainView(v => (v === 'chats' ? 'cards' : 'chats'))}
  focusedSourceIds={focusItemIds}
  onFocusSources={handleFocusSources}
  openConversationRequest={openConvoReq}
/>
```

- [ ] **Step 2: ContentGrid focus precedence**

In `ContentGrid.tsx` add to the props interface and destructuring:

```ts
// Focused citation ids from a chat answer; overrides search filtering entirely
focusItemIds?: string[] | null;
```

Change the ranking block (currently builds `searchRank` from `serverResultIds`):

```ts
const rankIds = focusItemIds ?? serverResultIds;
const searchRank = rankIds ? new Map(rankIds.map((id, index) => [id, index])) : null;
const focusActive = Boolean(focusItemIds);
```

And in the filter's search stage:

```ts
if (searchRank && (focusActive || !item.isOptimistic)) {
  return searchRank.has(item.id);
}
return !focusActive && itemMatchesSearchQuery(item, searchQuery);
```

(The existing sort-by-rank block already orders by `searchRank`, which now covers focus order too. When focus is active the empty-state "No results found" copy can only appear if none of the cited items are loaded — acceptable.)

- [ ] **Step 3: Typecheck and full suite**

Run: `npx tsc --noEmit -p tsconfig.app.json && npm test`
Expected: clean/green.

- [ ] **Step 4: Commit**

```bash
git add src/pages/Index.tsx src/components/ContentGrid.tsx
git commit -m "feat(chat): conversations view + focus-sources wiring on the library page"
```

---

### Task 8: Docs — retire routing, document sessions

**Files:**
- Modify: `docs/PLATFORM_API.md` ("Message routing convention" section, ~line 96)
- Modify: `docs/ui-changes.md` (new entry at top)

- [ ] **Step 1: Replace the routing section in PLATFORM_API.md**

Replace the whole "## Message routing convention (chat surfaces)" section with:

```markdown
## Message routing convention — RETIRED 2026-08-27

Chat composers are retrieval-only on every platform: all input goes to
`chat-with-all-content`. The old convention (URL → `add-url`,
`remember:`/`save:`/`note:` → `add-note`) is retired; capture belongs to
capture surfaces (input panel, share sheets, extension, SMS). Web has removed
`moleRouting.ts`; iOS should remove `StashKit/MessageRouting.swift` usage from
its Ask composer to match. Do not build new clients on message routing.
```

Also add under the chat endpoint section (after the citations paragraph):

```markdown
Sessions: conversations are time-gap sessions — a client convention. Pick the
user's latest conversation by `last_message_at`; continue it if the last
message is under 3 hours old, otherwise insert a new `conversations` row
(title null; auto-title it from the first question via `generate-title`).
Send only the current session's messages as `conversationHistory`. A DB
trigger maintains `last_message_at`; `list_conversations()` (SECURITY
INVOKER, RLS-scoped) returns the history list with counts and previews.
```

- [ ] **Step 2: Add the ui-changes.md entry**

New entry at the top (below the header/intro), matching house style:

```markdown
## 2026-08-27 · Chat sessions, retrieval-only mole, Conversations view, focus sources (web + contract)

Spec: `docs/superpowers/specs/2026-08-27-chat-sessions-design.md` ·
Prototype: `docs/superpowers/prototypes/2026-08-27-chat-workspace.html`

- **Sessions (all platforms — client convention):** a conversation is a burst
  of activity; 3+ hours of silence starts a new one. Resolve on open AND on
  send: latest conversation by `last_message_at`, continue iff < 3h old, else
  create a row lazily on first send (`title` null → auto-titled from the
  first question via `generate-title`). Send only the current session as
  `conversationHistory`. Explicitly opened old sessions resume (gap exempt).
  DB: `conversations.last_message_at` (trigger-maintained) + RPC
  `list_conversations()` → `(id, title, last_message_at, message_count,
  preview)` (migration `20260827120000_chat_sessions.sql`, applied).
- **Mole is retrieval-only (product decision, all platforms):** capture
  routing removed from the web mole (`moleRouting.ts` deleted); composer
  placeholder "Ask your stash…". iOS: remove `MessageRouting` from the Ask
  composer to match. Capture belongs to capture surfaces.
- **"Earlier conversations"** link replaces the footer hint under the mole
  composer; it swaps the main pane between the card grid and a bucketed
  Conversations list (Today / Yesterday / This week / month / older). Row
  click loads that session into the mole (pinning it if minimized).
- **Focus sources:** answers with sources show "⌖ Focus sources (n)"; click
  filters the card grid to the cited items in citation order with a
  "Showing n cards from this answer · Clear" pill. Focus overrides search
  filtering while active and always switches the main pane back to cards.
  Works on reloaded history via `messages.source_items`.
```

- [ ] **Step 3: Commit**

```bash
git add docs/PLATFORM_API.md docs/ui-changes.md
git commit -m "docs(chat): sessions convention, routing retirement, conversations view + focus sources"
```

---

### Task 9: Full verification + manual checklist

**Files:** none created — verification only.

- [ ] **Step 1: Full automated pass**

Run: `npx tsc --noEmit -p tsconfig.app.json && npm test`
Expected: tsc clean; all suites green (moleRouting tests removed, chatSessions + ConversationsView tests added).

- [ ] **Step 2: Manual checklist against the dev server**

Run `npm run dev` (project is configured for port 8080; do NOT use port 3000) and verify, signed in as the dev user:

1. Expand the mole → it shows the LATEST session (or an empty thread if >3h since the last message), header shows its title.
2. Ask a question in a fresh session → answer streams; within ~2s the header updates to an auto-generated title; `conversations` has a new row with `title` set (check via the Conversations view).
3. "Earlier conversations" swaps the main pane to the bucketed list (toolbar hidden); the link toggles to "Back to your stash"; the legacy "Ask Stash" conversation appears with its message count.
4. Click an old conversation → mole pins/loads it; typing continues THAT conversation (verify in the list: its count grows, no new row).
5. "⌖ Focus sources (n)" on an answer → grid shows exactly the cited cards, pill appears; Clear restores; chip on a RELOADED (history) answer also works.
6. Focus while the Conversations list is open → pane switches back to cards, filtered.
7. Paste a URL into the mole composer → it is sent as a chat question (NOT saved); no "saved" card appears.
8. Leave the mole open, fake the gap (temporarily set `SESSION_GAP_MS` to 10_000 locally, wait, send) → thread clears and a new session row is created; REVERT the constant afterwards.

- [ ] **Step 3: Report**

Report checklist results honestly (per item). Any failure: fix before declaring the plan complete; re-run Step 1 after fixes.

---

## Self-review notes (done at plan time)

- Spec coverage: migration §Data model → Task 1; §Session resolution → Tasks 2–3; §Auto-titles → Task 4; §Mole changes → Task 5; §Conversations view → Task 6; §Focus sources + Index → Task 7; §Cross-platform contract → Task 8; §Testing → Tasks 2/6/9. Spec's "ChatMole component test with mocked clock" is deliberately downgraded to util tests + manual item 8 (repo convention: no ChatMole component tests exist; the gap logic lives in the tested pure util).
- Facts verified against prod/code before writing: `generate-title` takes `{content}` → `{title}`; `conversations` has owner-scoped UPDATE RLS (client title PATCH works); `date-fns` is a dependency; current ChatMole line anchors (loadHistory ~74, persistMessage ~121, handleSend ~311, header ~379, footer hint ~571).
