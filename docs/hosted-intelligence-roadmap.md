# Stash intelligence: hosted quality pilot and product roadmap

Owner: Stash infrastructure. Date: 2026-10-09.

## Architecture decision

Use a dedicated Fly Sprite (`stash-quality`) for pinned Hermes one-shot jobs,
with Supabase owning the schedule, job leases, evidence, and reports. Hermes is
the investigator. Typed Stash services own retrieval, persistence, and product actions.
This keeps the same job contract usable when a larger, always-running worker
is needed. No local Codex scheduler is part of this production architecture.
Long investigations should persist intermediate evidence and continue as
bounded steps. The initial 90-second audit job is a first integration slice;
it is not an implementation of resumable, multi-hour research.

```mermaid
flowchart TD
  Save[User saves one object] --> Capture[Stash capture API]
  Capture --> Items[Items and source evidence]
  Items --> Enrich[Existing enrichment and repair queue]
  Enrich --> Items
  Cron[Supabase hourly schedule] --> Queue[Audit job with immutable evidence]
  Items --> Queue
  Queue --> Wake[Authenticated HTTP wake]
  Wake --> Supervisor[Fly supervisor: one leased job]
  Supervisor --> Retrieve[Daily investigation: one public rendered page]
  Retrieve --> Evidence[Durable source text and image candidates]
  Evidence --> Hermes[Hermes: bounded evidence review]
  Supervisor --> Hermes
  Hermes --> Proxy[Job-scoped model proxy in Supabase]
  Hermes --> Findings[Findings and proposed improvements]
  Findings --> Validate[Validate schema, scope, evidence and lease]
  Validate --> Results[Durable results]
  Results --> Daily[Daily report outbox]
  Daily --> Will[will@gostashit.com]
  Results -. evaluated proposal .-> Playbook[Versioned playbook and regression cases]
  Playbook -. approved release .-> Enrich
```

The last two arrows are the next phase, not an automatic deployment loop.

## Initial pilot (superseded by the fleet release below)

- Hourly, sample two recent links and one older incomplete link in explicitly
  configured pilot accounts, falling back to a third recent link. Read captured
  text and existing enrichment attempts.
- Check source support for titles, descriptions, and summaries. Flag missing
  evidence, contradictions, suspicious access-wall text, and useful next steps.
- A truncated source must be labeled. Missing support is not proof that a
  claim is false. Text-only audits cannot verify that an image depicts the
  right product, nor establish live-page availability.
- Report each finding with the item, cited source, evidence, uncertainty, and
  proposed action. The backend accepts only the job's allowed item/source scope.
- Store findings without changing saved items. Send the prior New York calendar
  day's immutable report after 09:00, with provider idempotency on retries.
- Initial runtime: one concurrent job, 90 seconds including cleanup, six model
  requests, 4,096 output tokens per request, fixed `gpt-4.1`. These bounds keep
  the first HTTP-triggered pilot within the hosting lifecycle and prevent
  runaway retries. A timeout remains a recorded failed attempt.
- Hermes has zero enabled tools. Hourly audits use captured snapshots; one daily
  live investigation uses a backend-owned public browser render, then Hermes
  reviews the recorded evidence. This is not open-ended web research.

### Daily live investigations

The daily `research` job selects one incomplete sampled link (or a missing-body
link, then the first sample). Supabase reserves a retrieval attempt before calling
Stash's existing Firecrawl provider. It sends only that exact source URL, preserving
product variant parameters, with no session cookies, browser actions, or source
credentials. It does not give Hermes a provider key or arbitrary network access.

The backend records bounded text, source time, outcome, attempts and at most five
image candidate URLs. Authwalls, unavailable sources, and wrong-page responses
remain explicit outcomes. Retries reuse an immutable observation; at most three
provider requests can be reserved for a job across all worker retries. The single
render has a 23-second outer deadline inside the existing 90-second job deadline.
Hermes receives only the remaining time after retrieval.

Live citations must identify the recorded item and source and quote its captured
text. They are checked separately from citations to the older saved snapshot.
A later price change does not prove that the original capture was wrong. Image
association comes from publisher markup, product identifiers and selected colour;
it does not verify pixels, storage success, or Stash's displayed image. The daily
report includes retrieval outcomes and candidate URLs with those limits.

The normal metadata endpoint now uses the same product-aware candidate selector:
product/variant evidence wins over generic imagery, and navigation campaign assets
are rejected. This changes future metadata selection; it does not silently replace
an existing user's saved image.

The Sprite sleeps when idle. The external request wakes its registered Service
and remains open during the bounded run. Postgres leases recover interrupted
work; a timer inside a sleeping Sprite cannot provide the hourly schedule.

## Fleet release — 2026-10-09

The hourly auditor now rotates across all eligible accounts, one account per job,
with up to three less recently reviewed links. It still performs at most one
scheduled audit an hour and one investigation a day. This broadens eligibility;
it does not mean every item is reviewed every hour. An account is eligible when
it has a recent public link or a previously assessed incomplete link.

The daily investigation can try Firecrawl, then Jina, plus exact-article Medium
public-feed artwork under one 23-second deadline. Source-specific canonical URL
matching accepts the same Medium article or YouTube video while retaining product
variants and playlist context. Each strategy records its outcome and duration.
Images remain candidates until actual storage/pixel checks establish more.

The 09:00 America/New_York email now includes actual save-cohort quality states
for all object types, incomplete source counts, and strategy attempt outcomes,
latency and available cost data. These are separate from Hermes' sampled factual
findings. Repeated identical detailed findings are collapsed. Other accounts'
URLs, quotes and model free text stay out of email; their category/severity counts
and proposal counts are included. Detailed email content is restricted to the
configured account allowlist. Source deletion purges associated report payloads;
the minimal delivery receipt remains to prevent duplicate sends.

Next work remains: versioned experiment proposals with held-out evaluations,
image-pixel verification, structured fact extraction and user-facing beta actions.
Hermes does not autonomously publish code or playbooks in this release. It produces
reviewable proposals with regression cases and acceptance checks. Open-ended web
research, resumable multi-hour investigations and personal/cross-user graphs are
not yet implemented.

## Evidence and typed-facts release — 2026-10-10

- Daily investigations now check the first associated image from an explicit public
  CDN allowlist. The extra request has a five-second / 5 MiB budget and records
  PNG/JPEG/WebP structure, dimensions, MIME, byte count and SHA-256. This is file
  validation, **not full image decoding or semantic image matching**. Unsupported
  hosts and failures remain explicit outcomes in the stored evidence and email.
- The model proxy enforces a closed JSON response schema, while exact quotes and
  item/source scope still pass independent checks. Hermes retries receive a closed
  validation-error code plus corrective instructions.
  The same three-attempt, six-model-call and 90-second limits remain. A failed quote
  must be copied correctly or omitted, never accepted by weakening evidence checks.
- `services/enrichment-evals/` exercises the actual selectors and source gates with
  22 labelled cases, including positive controls. CI writes per-case outcomes and
  implementation/corpus hashes. These are curated known regressions, not a held-out
  benchmark or a population accuracy measurement. Candidate releases must pass this
  gate; autonomous strategy promotion remains future work.
- Publisher JSON-LD now supplies source-bound `attributes.object_facts` for products
  and places. Product fields include brand, identifiers, selected variant, material,
  price/currency and availability when supported. Place fields include address,
  coordinates, cuisine and price range. Ambiguous objects, unrelated offers and
  unproven selected-variant prices are omitted; archive prices are not presented as
  newly observed prices. Facts join the item's searchable enrichment text.
- The web detail panel shows these facts as beta, with source and observation date.
  Compare retailers / Find similar open a web search; Open map uses the extracted
  address or coordinates. No claim of a cheaper verified offer is made.
- New captures through add-url (including capture/share-sheet clients), and legacy
  web capture, persist facts using an owner-scoped atomic attribute update that
  preserves unrelated fields and refuses stale sources, changed facts and field locks.
  Existing saves are not bulk backfilled in this release. Native clients receive the
  stored facts but need their own UI release to display the new section.

Next: independent image-identity evaluation, consent-appropriate held-out samples,
reviewable experiment records/canaries, controlled historical fact backfill, and
entity links for personal grouping. Graphs and automatic playbook publishing are
not part of this release. Daily email remains after 09:00 America/New_York.

## Transcript providers at save time — 2026-10-10 (handoff from the web agent)

YouTube (Firecrawl v2, fresh scrape), TikTok (SearchApi `tiktok_transcripts`) and Instagram
Reels (TranscriptFetch) transcripts are captured in `scrape-page-content` at save time and
marked with `attributes.enrichment.evidence.transcript = true`. The maintenance loop's
Supadata step, the TranscriptFetch 202 case, the chrome backfill and the evidence checks
are yours to align: see `docs/hosted-intelligence-transcripts-2026-10-10.md`.

## Improvement loop

1. **Measure:** distinguish missing fields, blocked sources, wrong identity,
   stale facts, unsupported summaries, image mismatch, and failed storage.
   Keep attempt-level strategy, reason, duration, cost, and evidence.
2. **Investigate:** group failures by source and object type. Give Hermes a
   small reproducible failure set, permitted tools, and an explicit budget.
3. **Propose:** return an explanation, technique, expected benefit, limits,
   source citations, and concrete regression cases. Version every playbook.
4. **Evaluate:** compare the candidate with the current playbook on a held-out
   corpus. Check wrong-image and unsupported-fact rates as well as coverage.
5. **Release:** canary a passing candidate, track regressions, retain rollback.
   Model-generated success labels do not substitute for verified examples.
6. **Optimize cost:** reuse fresh source facts and conditional requests; move
   expensive techniques later only after measuring their incremental benefit.

Escalation order should be source-specific: cached verified evidence → direct
HTML/structured data → supported source/API/reader → clean rendered browser →
public archive or corroborating search. Search results identify candidates;
they must not silently supply a different product's picture or a stale price.
Preserve product ID, selected variant, canonical URL, source time, and image
provenance. An honest incomplete result is preferable to an unrelated image.

For the jacket regression, success requires the navy MF26XS49 product/variant,
a verified asset stored in Stash storage, and the same selected image in the
card and details panel. A generic brand campaign photo fails the test.

## Roadmap beyond quality

| Stage | Data to establish | User-facing result | Evidence to advance |
|---|---|---|---|
| 1. Typed facts | Object identity, facts, provenance, confidence, observed time | Accurate richer cards, beta actions | Verified field accuracy by object type |
| 2. Personal graph | User-to-item events and item-to-entity links | Related items and useful recall | Relevant suggestions, correction/dismissal rates |
| 3. Suggested views | Overlapping themes with reasons and stable identities | Tabs such as vacation, NYC, dining, AI repos | Users keep/use the view and understand membership |
| 4. Object actions | Inferred intent and typed action proposals | Grocery lists, study guides, calendar drafts, related products | Useful completed actions, factuality and feedback |
| 5. Cross-user discovery | Separately permitted shared signals | Similar public posts from similar interests | Consent, access controls, diversity and usefulness |

Start with Postgres entity/edge/event tables and existing embeddings. A separate
graph database is an option when measured query needs justify it; Hermes
conversation memory must not become the canonical taste graph.

### Facts and useful beta actions by object type

| Object | Discrete facts (with evidence) | Proposed additions |
|---|---|---|
| Apparel, accessories, jewelry | Brand, product/SKU, variant, color, material, size, price/currency, retailer, availability, price time | Same variant elsewhere, lower verified price, similar items |
| Place, business, map image | Resolved entity/place ID, address, coordinates, locality, category, cuisine, price tier, confidence | Map, related saved places, itinerary suggestions |
| Paper or technical article | Title, authors, DOI/arXiv ID, date, methods, findings, limitations | Explainer, flashcards, study guide, related papers |
| Recipe or food video | Dish, ingredients/amounts, servings, steps, transcript timestamps, stated dietary facts | Scaled grocery list, related recipes, editable cart draft |
| Book photo | Title, author, edition/ISBN, recognition confidence, sourced rating and timestamp | Correct Kindle edition, reading context, related books |
| Event/estate-sale image | Organizer, address, start/end, timezone, extraction confidence | Calendar draft, directions, reminder |

A price comparison must include variant, currency, shipping/tax assumptions,
availability, and retrieval time. A map screenshot may be ambiguous: keep
candidate matches and ask only when needed to resolve identity. A saved place
does not establish a visit; a saved product does not establish ownership.

### Proposed data contracts (future migrations, not present features)

- `source_resources` and snapshots: canonical identity plus relevant variant
  parameters, freshness policy, content hash, retrieval method and timestamp.
  Public resource reuse is distinct from private user saves and annotations.
- `object_facts`: item/entity, predicate, typed value, evidence reference,
  confidence, observed time, extractor version, and user-correction lock.
- `user_item_events`: save, open, explicit feedback and completed actions,
  with time and source. Weight explicit signals above inferred ones.
- `user_entity_edges`: derived interests with supporting events, recency and
  uncertainty. Deleting evidence must remove or recompute derived interests.
- `suggested_views`: query/criteria plus referenced items and inclusion reasons;
  users can rename, dismiss, or pin them. One item can appear in several views.
  This does not revive `type='collection'` or require filing during capture.
- `action_proposals`: typed action, required inputs, evidence, expected output,
  status, and feedback. Generated artifacts retain a link to their source item.
  Calendar writes, purchases and orders require the user's action to execute.

Personal suggestions should explain "because you saved…" and allow correction.
Cross-user features require a separate sharing/consent boundary and must not
expose private saves or silently remove tenant filters. Sensitive inferred
traits should not become recommendation features. Build deletion and retention
into each derived table before enabling it.

## Observability and acceptance

Report sampled factual issues separately from whole-pipeline failure rates.
The pilot's three-link sample is not representative of all saved items.
The later dashboard needs denominators by time window, object type, source and
strategy: attempted, complete, partial, blocked, uncertain, verified incorrect;
plus latency, retries and cost per accepted improvement. Sampled accuracy must
show sample size, selection method, and evaluator version.

Hosted activation is proven only after a real leased audit completes, the
same completion can be retried safely, a stale worker is rejected, an hourly
trigger wakes an idle host, and a daily report is accepted by the mail provider.
Keep the local reviewer until that handover is verified; avoid parallel repair
owners. The existing repair queue remains unchanged by this pilot.

## Primary references

- [Hermes v0.21.6](https://github.com/NousResearch/hermes-agent/releases/tag/v0.21.6), pinned commit `818c13be1dc4fd28987e1e881a9408224afd4535`.
- [Fly Sprite lifecycle and services](https://docs.fly.io/sprites/working-with-sprites).
- [Hermes one-shot parser](https://github.com/NousResearch/hermes-agent/blob/v0.21.6/hermes_cli/_parser.py).
