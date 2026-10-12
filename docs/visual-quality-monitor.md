# Visual quality monitor

The hosted monitor checks the image delivery routes selected by Stash's web cards
and details. Supabase owns its queue, leases, budgets, captures and reports. It
runs independently of the existing Hermes text-audit worker and any local Codex
session.

## Schedule and evidence

- The `hosted-visual-monitor` cron wakes `quality-visual` every five minutes,
  offset from the text-audit dispatcher. Each wake handles one leased job.
- Each UTC hour schedules at most one rotating real-save sample and one rotating
  approved canary. Real samples rotate across accounts and eligible saved links.
- Canaries authenticate as a dedicated monitor account and call the normal
  `capture → add-url` pipeline. They are private, retain a stable capture receipt
  across retries, and settle on later wakes before comparison.
- Card and detail delivery are inspected separately. The report records the
  delivered URL, source URL, hash, dimensions, reference version and comparison
  method. Identical images can reuse one model assessment.
- Unchanged approved-reference bytes yield `exact_match`. Different bytes use a
  fixed vision model; confidence below 0.85 yields `inconclusive`. Model confidence
  is not a calibrated accuracy estimate. Source-only comparisons have no approved
  reference and are labeled `vision_source`.
- Paid requests require a durable reservation before each call: at most two per
  job, four per UTC hour, and 48 per UTC day. Failed provider requests consume a
  reservation; there is no inline paid retry.

The existing daily email includes a **Visual accuracy monitoring** section after
09:00 America/New_York, covering the previous local calendar day. Detailed
real-save findings follow the configured report account allowlist; other accounts
contribute counts only. Canaries and real-save samples have separate totals.
Zero checks, unavailable images and pending jobs never count as passes. The email
outbox's accepted state confirms provider acceptance, not inbox delivery.

## Deployment and activation

1. Verify current remote function sources and migration history. Apply only
   `20261012010000_visual_quality_monitor.sql` after a dry run; do not repair or
   overwrite unrelated migration history. The migration also adds the visual
   projection to the existing daily-report snapshot. The new cron starts inactive.
2. Provision a dedicated Stash Auth account with access to the normal save
   entitlement. Register its UUID in `hosted_visual_config.monitor_user_id`.
   Keep its credentials only in backend secrets:
   `QUALITY_CANARY_USER_ID`, `QUALITY_CANARY_EMAIL`, `QUALITY_CANARY_PASSWORD`.
   Never install them in Hermes or expose them in logs.
3. Retain the project's existing `CRON_SECRET`, `OPENAI_API_KEY`, Supabase service
   credentials and public anon key. Use `QUALITY_REPORT_SCOPE_USER_IDS` for detailed
   email eligibility, or the existing `QUALITY_SCOPE_USER_IDS` fallback.
4. Deploy `image-proxy` first, then `quality-visual` and the updated
   `quality-dispatch`. Preserve existing authentication settings: the visual
   endpoint validates `x-cron-secret` itself. Do not add a local scheduler or
   replace the Hermes Sprite service.
5. Provision reviewed references as below. Enable `QUALITY_VISUAL_ENABLED=true`
   only after configuration and endpoint authorization checks pass.
6. Confirm an unauthenticated visual wake is rejected, then exercise a real
   authenticated wake. Activate the named cron with `cron.alter_job` only after
   those checks; the migration deliberately leaves it inactive. Verify durable
   job capture, settlement, comparison, report projection and cleanup. A successful
   function deployment alone does not prove paid vision calls or live canaries work.

## Provisioning a known-good reference

A baseline is reviewed evidence, never an automatically accepted result of the
current enrichment pipeline.

1. Inspect the exact public source and its intended main image. Preserve meaningful
   URL parameters, including product variants. Record source URL, review time,
   image provenance and a plain description of the expected image.
2. Save the reviewed JPEG, PNG or WebP bytes, at most 5 MiB, in the **private**
   `quality-reference-images` bucket. Use `<fixture-id>/v<version>.<extension>`.
   Upload without upsert; do not overwrite a versioned asset.
3. Compute SHA-256 over those exact stored bytes and add a
   `hosted_visual_baselines` row with `id`, `version`, `title`, `source_url`,
   `image_path`, `sha256`, `description`, `provenance` and `reviewed_at`.
4. Enable the reviewed version. Baseline rows are immutable except `enabled`;
   changes require a new reviewed version and a transaction that disables the old
   version before enabling the new one. Keep old versions while jobs reference
   them. A mismatch never automatically promotes a replacement.

The collector verifies stored reference bytes against the approved hash before
using them. Missing, oversized, corrupt or changed references produce inconclusive
results; they cannot fall back to an apparent source-only success.

## Delivery protections and limitations

Owned images must belong to the sampled account's storage prefix. Remote images
use a fixed CDN allowlist; unsupported hosts remain unavailable. Downloads are
bounded to five seconds and 5 MiB. MIME, raster structure and dimensions are
checked before bytes are sent to the fixed vision model.

The card proxy uses the same delivery URL with
`X-Stash-Visual-Monitor: 1`. That mode disables redirects on the actual upstream
fetch, caps its entire body download, disables caching, and returns
`X-Stash-Visual-Mode: no-redirect`. The collector requires the response marker;
old deployments, ordinary cached responses and redirect-dependent images fail
closed. Normal browser requests retain their existing behavior. Therefore a
monitoring redirect failure is unknown delivery evidence, not proof a user's
browser failed to load the image.

This release covers **link image delivery and semantic image association**.
It does not run a browser, inspect CSS cropping or layout, evaluate video playback
or embedded-frame pixels, or certify every saved item. Repository plates and
embeds are explicitly unsupported surfaces. Vision judgments are proposals for
review; user items and playbooks are not automatically changed.

## Cleanup, inspection and rollback

Inspect `hosted_visual_jobs`, `hosted_visual_model_calls`, the
`hosted_visual_report` RPC, daily report snapshots/outbox, and the
`hosted-visual-monitor` cron execution history. Failed jobs retain closed reason
codes. Reference hashes and versions remain available after temporary canary
images disappear; report URLs to those temporary images can then expire.

Canary deletion requires its registered job, dedicated owner, private visibility,
settlement and expected image path. A media-cleanup tombstone survives item
removal so the next wake can retry failed storage deletion. Only unreferenced
owned generated preview paths are removed. Ordinary user items, remote images
and approved references are never cleanup targets. A bounded sweep also removes up to 20 intermediate generated previews per wake
from that dedicated account, only after 24 hours and only while unreferenced.
Monitoring records have a
35-day retention window; outstanding canary cleanup is retained for retry.

To stop new checks and paid work, set `QUALITY_VISUAL_ENABLED=false`. Keep the
cron and monitor account configuration present so cleanup and retention continue.
Do not delete baseline rows, model-call accounting or cleanup tombstones to reset
a failure or budget. If rollback of the proxy is necessary, disable visual work
first; a collector paired with an older proxy will deliberately return unavailable.
The existing text-audit schedule and daily reporting can remain active.
