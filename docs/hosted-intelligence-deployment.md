# Hosted quality pilot — deployment record

Date: 2026-10-09. Branch: `codex/hosted-intelligence`.

## Infrastructure

- Supabase project: `uqqsgmwkvslaomzxptnp` (Stash).
- Fly organization: `will-dzierson`; dedicated Sprite: `stash-quality`.
- HTTP service: `https://stash-quality-b2uis.sprites.app`.
- Hermes: `v0.21.6`, commit `818c13be1dc4fd28987e1e881a9408224afd4535`, installed with its official package manager.
- Worker: Node 24, registered Sprite Service, separate `stash-hermes` UID.
- Backend: `quality-worker`, `quality-dispatch`, `quality-model`, and the product-aware `extract-link-metadata` update.
- Migrations: `20261009120000_hosted_quality`, `20261009121000_hosted_quality_cron`,
  `20261009130000_hosted_quality_delivery_receipts`,
  `20261009150000_hosted_quality_live_evidence`.

The existing repo and remote migration histories differed. Deployment used an
isolated folder populated with `supabase migration fetch --linked`, followed
by the new migrations, with separate dry runs listing only those changes. No remote migration
history was repaired and no unrelated migrations were applied.

## Configuration

The pilot is scoped to Will's existing Stash account. `QUALITY_RESEARCH_ENABLED`
is now true: one daily live page investigation supplements hourly snapshot audits.
The daily recipient is `will@gostashit.com`; the sender uses Stash's
existing Resend configuration. The dispatcher runs every five minutes to wake
work and retry the outbox, with one unique audit job per UTC hour. The daily
report covers the previous America/New_York day and is prepared after 09:00.

The HTTP route is reachable by Supabase and enforces a separate wake token.
The worker API uses a different scoped token. Both are kept in backend secrets
and the root-only worker configuration. Hermes receives only its expiring job
lease capability for the model proxy. OpenAI, Resend, service-role and Fly
management credentials are not passed to Hermes.

## Verification log

- Queue migration executed in disposable PostgreSQL14; assertions covered
  isolation, scope, leases, retries, model budget, completion idempotency,
  email idempotency, deletion and retention. Test transaction rolled back.
- 23 supervisor tests, four model policy tests and 16 backend tests passed (43 total).
- Pinned Hermes `--help` succeeded under the restricted UID.
- Registered service started; external `/health` returned 200 and an
  unauthenticated `/run` returned 401. Worker API rejected an unauthenticated
  claim with 401. Disabled model proxy returned 503.
- First real dispatch sampled three items and reached the worker. Hermes
  initially chose `/v1/responses`, while the proxy permits Chat Completions;
  the attempt failed before any accepted model call. Paid work was paused
  during adapter diagnosis. This was an integration failure, not a finding
  about saved-item quality.
- Corrected the pinned Hermes adapter to select Chat Completions explicitly
  and use its supported zero-tool configuration. The installed runner then
  completed a synthetic local-API test under the restricted UID with zero
  tools; this verified the actual subprocess and protocol, beyond `--help`.

- A real production audit completed: job `415314ba-a2d0-404e-a5c6-b4205254f5a9`,
  three sampled links, one proposed finding, two model calls. It distinguished
  supported source text from an item with missing source evidence. Dispatch
  request 5166 returned HTTP 200.
- Initial Hermes token telemetry returned 0/0 despite model calls. The deployed
  proxy now requests streaming usage and the worker records unavailable/all-zero
  counts as unknown. A second hourly audit
  (`6e1625c9-9e12-4a99-aa22-1d641b2dd350`) completed and recorded 5,815 input
  and 363 output tokens. Do not interpret unknown usage as free operation.
- Delivery receipts retain minimal recipient/day/version accounting after
  source deletion so a purged report cannot cause a second daily send. The
  private report content is still removed. Database regression tests cover
  accepted and uncertain delivery, backfill, retry and retention.

- Re-submitting the completed production result returned
  `{"ok":true,"status":"completed","idempotent":true}`. A heartbeat with a
  different fence returned `{"ok":false,"error":"lease_lost"}`.

- At 07:10 UTC, the scheduled dispatcher sent the one-time pilot activation
  report to `will@gostashit.com`. Outbox
  `d6569869-fb0f-40ec-ac4c-439a0543ebfc` is `accepted`, one attempt, no error;
  Resend message `01a11f7f-5520-7833-b87c-1295498f4160`. Provider acceptance is
  not proof of inbox delivery. The regular daily report remains scheduled
  after 09:00 America/New_York.
- An explicit service-stop test left the service stopped, as a manual stop
  is different from idle hibernation. The service was restored at 07:11 UTC.
- Fly control-plane inspection then reported the host `cold`. With no intervening
  exec or HTTP request, the 07:15 UTC Supabase cron woke the service: network
  response 5173 was HTTP 200, `dispatched`, no timeout, no error. This verifies
  scheduled wake from idle; explicit operator stops still require a start.
- Local automation `review-stash-enrichment-hourly` was set to `PAUSED` after
  the hosted audit, mail acceptance, and cold-host wake checks. This pilot
  replaces local scheduling; its initial coverage is narrower (text-only
  snapshots, not live research or image verification).

## Daily live investigation and product images — 2026-10-09

Migration `20261009150000` was applied after an isolated-history dry run listed
only that migration. The updated quality backend, dispatcher, metadata function,
and Sprite runtime were deployed. The shared selector received a final regression
fix for products named Logo/Icon/Pixel; both functions importing it were redeployed.

- A research job gets one bounded Firecrawl render of a sampled link, with the
  existing provider credential held only in Supabase. Evidence is persisted
  before Hermes reviews it. Source mismatch, access walls and failures remain
  explicit outcomes. Image associations are not automated pixel verification.
- The 07:45 UTC scheduled run completed research job
  `bd6bae1d-51cb-4fb2-b835-5d027a51efc5` in about 17 seconds. Firecrawl recorded
  `source_identity_mismatch` for a Medium article in 5,158 ms. Hermes returned
  no unsupported findings and explicitly reported unavailable source evidence.
  Usage: two model calls, 5,925 input and 167 output tokens. This proves the
  scheduled retrieval → stored observation → model review flow, not successful
  article recovery or live-source citation on that page.
- Manual dispatch verification request 5184 returned HTTP 200, `dispatched`.
  Daily deduplication prevented a duplicate research job. The daily report
  projection includes retrieval outcomes without copying raw fetched bodies.
- A production read-only probe of the exact Peter Millar URL with navy/XXL
  parameters first returned HTTP 403 through the fast fetch. The final deep
  path returned the correct title and `MF26XS49_NAV.jpg` via
  `jina-reader-rescue`. Browser inspection of that image confirmed the navy
  hooded sweater jacket matches the user's screenshot. This was manual visual
  verification; the worker does not yet inspect image pixels.
- No matching Peter Millar saved link was returned for the pilot account in the
  scoped database check. No old card was rewritten or recreated; no claim is
  made that its stored preview was repaired.
- Final verification: 33 worker/model policy tests, 56 collector/backend tests,
  and 95 image-selection/metadata tests passed (184 total). Both PostgreSQL
  suites passed, including durable evidence, lease fencing, bounded reservations,
  report privacy and unsafe-URL redaction. Type checks and diff checks passed.

The pilot still proposes changes only. It does not autonomously change items,
publish playbooks, search for new scraping techniques, or estimate population-wide
accuracy. Exact URL identity is deliberately conservative and may reject valid
canonical redirects; evaluating evidence-backed redirect equivalence is a next
step. Owned image storage and automated visual matching also remain to be built.

## Operations

Pause paid work with `QUALITY_ENABLED=false` in Supabase secrets. The cron
continues retention cleanup; no new jobs can be claimed and the model proxy
rejects requests. Existing Stash enrichment and repairs are separate.

Inspect `hosted_quality_jobs`, `hosted_quality_evidence`, `hosted_quality_results`,
`hosted_quality_reports`, `hosted_quality_outbox`, and the
`hosted-quality-dispatch` cron history through authenticated admin access.
Provider acceptance is not proof of inbox delivery; bounce/delivery webhooks
are not part of this first slice.

See [roadmap](hosted-intelligence-roadmap.md) for next phases and the limits of
snapshot auditing plus bounded daily live investigations.
