# Ask retrieval reliability + inbound intent gate

Date: 2026-08-29 · Status: approved 2026-08-30; R1–R4, R6, G1–G3, G5 implemented
2026-08-30 (R5 doc2query/audio-titles and G4 web chip are follow-ups)
Owner surfaces: `chat-with-all-content`, `twilio-webhook`, `hybrid_search_content`,
enrichment pipeline; later web/iOS Ask UI.

## Why now (evidence)

Reviewed real conversations from 2026-08-30 (conversation
`18e50ab5-a9c1-4605-a3a2-1b2ff6314060`): three retrieval misses in one session,
each recovered only after the user rephrased. Reproduction against production
data proved the pipeline itself was fine — the unfiltered hybrid search ranked
the right item **#1** for the exact failed phrasing in both hard cases. The
misses were caused by the agent applying `types` filters keyed to the storage
taxonomy, which doesn't match user vocabulary:

- "…that I was making a **note** of" → `types:["text"]`, but a voice note is
  `type=audio`. Item was fully enriched + embedded 43s before the question.
- "do i have any **videos** about claude" → `types:["video"]`, but YouTube
  saves are `type=link` (with `attributes.link.flavor="video"` already
  recorded by enrichment — retrieval just never consults it).

A wrongly-filtered search returns plausible-looking wrong results, so the
model concludes the item doesn't exist instead of retrying unfiltered.

Corpus reality (2026-08-29): largest user = 508 items / 2,156 chunks; median
user ≈ 2 items. The whole catalog of any current user fits in one context
window (~30k tokens for 508 items at ~60 tokens/line). Retrieval strategy
should exploit this.

## Interaction styles Ask must serve

1. **Single word** ("claude") — lookup, not a question. Must never come back
   empty when a title/description contains the word.
2. **Direct question** ("who is the author of…") — agentic search + read.
3. **Fuzzy recall** ("that site with templates from a while ago") — user needs
   candidate offers, not a single confident answer. Presenting 2–4 candidates
   with "which one?" is correct behavior here, not a failure.

## Workstream R — retrieval reliability

**R1. Soft type filters.** `search_stash` filters stop being hard excluders.
Implementation: `runSearchStash` always runs the unfiltered search too (the
RPC is cheap at this scale); filtered hits rank first, unfiltered-only hits
follow, labeled (e.g. `— outside your "video" filter`). The model sees the
answer even when its filter guess was wrong. No client changes; SSE contract
unchanged.

**R2. Link flavor in search.** "video"/"article"/"product" requests match
`type=link` items via `attributes.link.flavor`. Either an RPC-level
`filter_flavors` param or post-filter in the edge function. The enrichment
already writes the fact; retrieval must use it.

**R3. Prompt vocabulary fixes** in `chat-with-all-content` system prompt +
tool description: voice notes are `audio`; "note" almost never maps to a type
filter; YouTube/Vimeo are `link`; require one unfiltered retry before ever
claiming something isn't saved.

**R4. `browse_catalog` tool** — the recall backstop that also serves
single-word and fuzzy-recall styles. Returns the user's entire catalog,
newest-first, one compact line per item:
`id · type(+flavor) · saved date · title · one-line description · tags`.
Cap: if the user has > ~1,500 items, return the most recent 1,500 and say so
(no current user is near this). The agent uses it when search feels wrong,
when the query is a bare word, or when the user is fishing ("what do I have
about…"). Item-level recall misses become structurally impossible.

**R5. Ask-what-you'll-be-asked enrichment (doc2query).** At save time,
generate 3–5 synthetic questions the item could answer and embed them as
additional chunks (marked `chunk_index >= 1000` or a `kind` column so they can
be regenerated). Closes the vocabulary gap ("author" appeared nowhere in the
reincarnation voice note; a synthetic question would contain it). Also: give
audio items a real title from the transcript (raw filenames are FTS poison
and read badly in citations).

**R6. Retrieval observability + golden set.** Log every `search_stash` /
`browse_catalog` call (query, filters, result item_ids) to a `retrieval_log`
table (service-role only). Replay a golden-question set against the RPC
before/after each change. Without this, nothing above is measurable.

Scope note — the golden set is a **system regression suite, not per-user
calibration**. The 2026-08-30 failures seed it because they exercised
structural bugs (filter-excludes-answer, vocabulary gap); each entry is kept
because it represents a *class* of query every user will hit (type-word
mismatch, absent-word FTS miss, single-word lookup, fuzzy recall), not
because one user phrased it. Nothing in Ask adapts to an individual's
phrasing. If per-user/behavioral adaptation is ever wanted, its input is the
aggregated `retrieval_log` across many users — a separate, deliberate
workstream, explicitly out of scope here.

Sequencing: R1–R3 are one small change set (migration + edge function). R4 is
edge-function-only. R5 touches enrichment paths + a backfill job. R6 first or
alongside R1.

Explicitly skipped (wrong scale/fit): RAPTOR, GraphRAG proper, self-hosted
late-interaction embedders, query-routing classifiers. Graph/temporal memory
(Graphiti / HippoRAG-style entity PPR) is deferred to the interest-graph
workstream — same foundation, bigger lift.

## Workstream G — inbound intent gate

Problem: a message arriving in a mixed channel (WhatsApp/SMS today; web/iOS
Ask input later) may be a thing to save or a thing to answer, and users won't
reliably say "remember…"/"note…". Today's `twilio-webhook/intentClassifier.ts`
is a forced 3-way choice (note/question/command), no confidence, ignores
media/URLs, silently defaults to `note` on error, and has no way to ask the
user — there's no pending state across messages.

Ethos constraint: lowest-friction capture. **Default is to act, not to
interrogate.** Confirm only on genuine ambiguity; after acting, offer a
one-word escape hatch.

**G1. Classifier v2** (shared `_shared/intentGate.ts`, usable by
twilio-webhook now and the Ask edge function later):

- Deterministic pre-checks before any model call:
  - bare URL (or URL + short non-question caption) → `save`, no confirmation.
  - media attachment with no text or a caption that isn't a question → `save`.
  - registered command words (existing command set) → `command`.
- Otherwise one cheap LLM call returning JSON:
  `{intent: save|ask|command, confidence: high|low, reason}` — message text
  plus signals (has media, has URL, prior message role) in the prompt.
- `high` → act on it. `low` → G2 confirm flow.
- Failure mode: classifier error on a text-only message defaults to `ask`
  with the saved-nothing reply including "say 'save' to keep it as a note" —
  answering wrongly is recoverable; silently mis-saving a question as a note
  (today's default) reads as the product not listening.

**G2. Confirm round-trip (WhatsApp/SMS).** On `low` confidence:

- Reply: "That looks like a note to save. **Save it**, or **answer it**?"
  Text prompt on both channels initially ("Reply 1 to save, 2 to answer");
  WhatsApp quick-reply buttons need a pre-registered Twilio Content
  template — worth doing, but a console/config task, so a follow-up.
- Persist pending state: `pending_intents` table
  (`user_id, phone_number, channel, payload jsonb, created_at`, TTL 15 min,
  one active row per user+channel — new inbound ambiguity replaces it).
- Next inbound message: if it matches a resolution token
  (save/keep/note/1 · answer/ask/2), execute the pending payload accordingly
  and delete the row. Anything else: treat the new message normally and apply
  the classifier's lean to the expired pending item, prefixing the reply with
  what happened ("Saved your earlier message as a note, by the way.").

**G3. Escape hatch after auto-acting.** Every auto-save reply appends
"— reply 'undo' to remove, or 'ask' to get an answer instead." `undo` deletes
the just-created item (pending_intents row of kind `undo`, same TTL); `ask`
routes the original text through the question handler. Mirror: an
auto-answered message gets "…say 'save' if you wanted to keep that."

**G4. Web/iOS Ask input (later phase).** Same classifier as a pre-pass in the
Ask composer: pasting a URL or note-looking text into chat renders an inline
chip — "Looks like something to save · **Save to Stash** / **Answer**" — as a
new optional SSE frame `data:{suggest:'save', reason}` (clients that don't
know the frame ignore it, per the existing optional-frame contract). Capture
surfaces stay capture-only; the gate never runs there.

**G5. Conversation memory for the gate.** The classifier receives the last
2–3 `sms_conversations` rows so "answer it" / "actually save that" and
follow-up questions classify correctly in the ongoing-thread world of SMS,
where we can't split sessions the way web/iOS chat does.

## Rollout order

1. R6 logging + golden set (measurement first).
2. R1–R3 (one deploy: migration + `chat-with-all-content`).
3. R4 `browse_catalog`.
4. G1–G3 in `twilio-webhook` (new `pending_intents` migration + shared gate).
5. R5 enrichment (doc2query + audio titles + backfill).
6. G4 web/iOS chip once the SSE frame is agreed in `docs/PLATFORM_API.md`.

Each shipped step gets a dated entry in `docs/ui-changes.md` (G2/G3 change
user-visible WhatsApp/SMS behavior; R-work is behavior-neutral except better
answers).
