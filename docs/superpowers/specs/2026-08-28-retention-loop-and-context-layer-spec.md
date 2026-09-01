# Retention loop & personal context layer — near-term requirements

**Date:** 2026-08-28 · **Status:** requirements captured from strategy session
with Will; **not yet scheduled**. Will kicks this off as a separate workstream
after the current foundational UX work. Builder agents: treat this as the spec
to plan from; write per-workstream plans in `docs/superpowers/plans/` before
touching code.

## Strategic context (why these, why now)

Two stories run in parallel:

1. **Visible product:** lowest-friction capture + "your memory, searchable."
   Its known failure mode (Pocket, Evernote) is the **guilt pile** — saving
   feels productive, retrieval never happens, users churn silently around week
   three. The retention loop (Workstream A/B) is the direct countermeasure and
   is the highest-leverage near-term product work.
2. **Scaffolded quietly alongside:** Stash as the **neutral, user-owned
   personal context layer for the agent era** — any agent the user trusts can
   query their stash/taste with permission (Plaid-for-personal-context). The
   MCP server (C), permission architecture (D), and taste-graph derivation
   discipline (E) are the scaffold. None of these compete with the visible
   product for correctness: A/B *consume* E, and C is a thin wrapper over
   retrieval infrastructure that already exists.

Monetization posture (standing decision): revenue flows on the **user's side**
(subscription; later, transaction/success fees when the user's own agent
converts). **Never** sell or share raw stash data with advertisers, merchants,
or brokers — including "user-priced" raw-graph sales. External parties may
eventually buy *answers* (metered, audited inference) or *publications*
(slices the user deliberately publishes), never *copies*. Neutrality and trust
are the moat; Stash revenue must never scale with data leaving the vault.

## Workstream A — Resurfacing engine + digest (the retention loop)

The engine is **system-initiated and zero-decision**; it covers 100% of saves.
User-set reminders (Workstream B) are optional metadata that feed it, not the
primary mechanism.

Requirements:

- **A1. Resurfacing scheduler.** A scheduled job (Supabase cron / scheduled
  edge function) selects items to resurface per user. Selection uses
  enrichment we already have — link flavor, content type, location, recency —
  because different objects have different natural half-lives (an article goes
  stale in days; a saved restaurant resurfaces when relevant, e.g. weekend or
  travel planning; a recipe on a weekend). Heuristics can start simple
  (type-based decay buckets); the contract is that selection is
  attribute-driven and improves as enrichment improves.
- **A2. Explicit intent wins.** An item with a user-set
  `attributes.resurface.remind_at` (see B) is surfaced at that time, ahead of
  any inferred schedule.
- **A3. Digest delivery — email first.** Email works across every surface
  today, before the iOS app lands, and is where this loop is proven
  (Readwise). Push notifications are a later delivery channel, not a
  prerequisite.
- **A4. Keep / Done / Let go.** Every resurfaced item carries three one-tap
  actions: **Keep** (resurface again later), **Done** (acted on; stop
  resurfacing, item remains), **Let go** (archive/release, guilt-free). "Let
  go" is a first-class anti-guilt feature: the pile forms when the only exit
  is confronting all of it at once; give a loud, cheap, per-item exit.
  Actions must work from the email (signed one-click links) without requiring
  an app session.
- **A5. Resurfacing state is data.** Store per-item resurfacing state
  (last-surfaced, response, next-eligible) in the `attributes` lane
  (whole-blob writes — preserve unknown keys) or a dedicated table if volume
  warrants; agent planning the work decides, but state must be queryable —
  it is future taste-graph signal (what the user keeps vs releases is
  preference data).
- **A6.** The digest is a future home for taste-graph-powered discovery; do
  not design it as email-only plumbing. Keep rendering/content selection
  separable from delivery.

## Workstream B — Post-save intent chips (capture surfaces)

Constraint from ETHOS: **no decision before or during capture, ever.** The
chip is offered strictly **after the save commits**, modeled exactly on the
location pattern: opt-in, one tap, structured-only, zero cost to decline.

- **B1. Pattern (all surfaces):** save fires immediately as today → transient
  confirmation ("Saved ✓") carries optional chips: **1 day · 5 days ·
  Someday** (copy TBD in UX pass) → self-dismisses after ~2–3s if untouched.
  A tap upgrades the already-saved item; no tap changes nothing. Never a
  pre-save flyout or menu that gates the save.
- **B2. Data contract:** tap writes
  `attributes.resurface = { remind_at: <ISO>, source: "user" }` via the normal
  item-update path (whole-blob attributes rule applies). Inferred scheduling
  (A1) uses `source: "inferred"` and must never overwrite a `source: "user"`
  value.
- **B3. Surfaces & order:** web capture UI and Chrome extension first (cheap;
  and they instrument what fraction of saves get explicit intent — this
  number decides how much iOS effort the chips deserve). iOS share extension
  rides with the planned visual-overhaul work: the share extension owns its
  own UI, so it uses the same save-immediately-then-offer pattern; capture is
  committed before any choice is shown.
- **B4.** One `docs/ui-changes.md` entry covers the pattern contracts-first
  for all platforms, per working agreements.

## Workstream C — MCP server (personal retrieval for agents)

- **C1.** Expose the existing retrieval stack (`search-items` / RAG pipeline)
  as an MCP server: tools on the order of `search_stash`,
  `get_item`, later `get_taste_profile(domain)` (consumes E). Thin wrapper;
  the server owns no new intelligence.
- **C2.** Access is per-user, token-scoped, and gated by the permission model
  (D). Ship behind an opt-in "Connect an agent" surface; this is both a real
  feature for the AI-forward early-adopter base and the scaffold for the
  context-layer story.
- **C3.** Read-only at first. Capture-via-agent already has canonical
  endpoints (`add-note`/`add-url`/`add-file`); if agent capture is exposed
  over MCP it must call those same endpoints, not new paths.

## Workstream D — Permission & audit architecture

Designed early because it cannot be retrofitted, and because every future
business model hangs off one primitive: the system natively distinguishes

- **copies** — raw data leaving the vault: *never supported, by
  architecture*, not policy;
- **answers** — metered, scoped query access (what MCP/agents get);
- **publications** — slices the user deliberately publishes (future
  tastemaker features).

Requirements: scoped grants per connected agent/party (e.g. topic-level
scopes: food & travel yes, health no); a user-readable audit log ("Claude
searched your stash for restaurants, Tue 2:14pm"); one-tap revocation.
Workstream C must launch on this, however minimal the first scope vocabulary.

## Workstream E — Taste-graph derivation (standing discipline + rollup)

- **E1. Standing rule for all enrichment work (all platforms, effective
  now):** every enrichment output lands as a structured, machine-consumable
  fact in the proper lane — never display-text only. This is a constraint on
  current work, not a new feature.
- **E2. Derivation layer:** a periodic per-user rollup job producing derived
  taste artifacts — interest clusters (from embeddings), place affinities,
  recurring entities — stored as first-class data. First consumer is our own
  product (A1 selection, digest content, "for you" resurfacing); second is
  C's `get_taste_profile`. No user-facing "graph" UI; the graph is
  infrastructure, not a product surface.
- **E3.** Resurfacing responses (A5: keep/done/let-go) feed derivation as
  preference signal.

## Sequencing

1. **A** (engine + email digest with keep/done/let-go) — the retention floor;
   ships value on all current surfaces with no iOS dependency.
2. **B** on web + Chrome extension (instrument explicit-intent rate).
3. **C + D minimal** (MCP read-only on scoped tokens + audit log).
4. **E2** rollup (E1 discipline applies immediately, throughout).
5. **B** on iOS share extension, with the visual-overhaul plan.

## Explicitly parked (decided, do not build now)

- **Raw taste-graph sales / user-priced data sales** — rejected outright (see
  monetization posture; buyer economics fail and pricing corrupts the signal).
- **Trend panel / aggregate data products** — viable later only as explicit
  opt-in panel, aggregate-only, paid membership; not now.
- **Professional verticals** (taste-intake professionals, evidence-grade
  capture) — promising, pending validation interviews; no build.
- **Healthcare/caregiver flavor** — real need, but implies shared stashes
  (multiplayer fork) + compliance burden; revisit only on organic signal.
- **A2A / agentic-commerce rails** — standards too unsettled; MCP is the only
  agent-facing protocol we build on today.

*Captured 2026-08-28 from strategy session with Will. Context: guilt-pile
analysis, agent-era context-layer strategy, monetization posture. Questions of
interpretation resolve toward `docs/ETHOS.md`; conflicts with it are flagged,
not shipped.*
