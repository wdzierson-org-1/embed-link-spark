# Stash — Claude / Codex coordination

**Updated by Codex: 2026-10-11 20:50 EDT.** Will has assigned **all iOS development to Codex, including Google and Apple authentication**. This supersedes earlier, narrower ownership entries below. Claude's acknowledgement of this handoff is **pending**; the ownership assignment comes from Will and is effective now. *(Claude: acknowledged 2026-10-12 14:22 EDT — see “Questions and acknowledgement”.)*

**Shared working copy:** `/Users/will/Appdev/embed-link-spark/docs/agent-coordination.md`. Read and update this absolute path even when implementing in another worktree. Worktree copies are snapshots, not separate coordination queues. Preserve dated entries; update current status and append an acknowledgement when a handoff is read. This follows the Gisted coordination structure without importing Gisted's services, credentials or release roles.

## Agents and ownership

| Owner | Territory | Coordination boundary |
| --- | --- | --- |
| **Codex — iOS lead** | All `ios/**`: SwiftUI app, authentication/session/profile flows, Share extension, capture, library/detail/media/Ask, persistence, accessibility, tests, dependencies, project/signing configuration, build and TestFlight preparation. | Claude should hand over any native work or findings rather than implement a second iOS solution. Codex owns the native auth phase previously called “iOS plan 18.” |
| **Codex — shared native code and macOS** | `ios/StashKit/**` and the native Mac rebuild in the `macos-capture` worktree. | StashKit serves both platforms. Preserve the active Mac changes before altering shared client, Keychain or App Group configuration. |
| **Claude — web and web auth** | `src/**`, web assets and web auth UX; any separately assigned browser-extension work. | Continue web work independently. Describe user-visible changes and native-facing contracts in `docs/ui-changes.md`; iOS parity implementation belongs to Codex. |
| **Claude — current auth backend handoff** | Existing provider configuration, OAuth profile migration, `apple-token-exchange`, `delete-account` and their shared auth helpers. | Claude is the initial contact for the web/backend auth work already delivered. Claim any further backend/config change here first. This is not a blanket reassignment of Codex's existing enrichment/backend work. |
| **Named implementer per change — shared backend/API** | `supabase/**`, migrations, auth settings, shared capture/enrichment contracts and cross-platform docs. | Record the exact owner, files and compatibility impact before edits. Resolve an existing overlapping claim with its owner; independent work can continue. |

### Verified source baseline

Read-only local audit, 2026-10-11; these are source findings, not a new release or production auth verification.

- Canonical checkout: `/Users/will/Appdev/embed-link-spark`, `main` at `98ea955d1c3b5327b878a7df1796b9f24d7c7b95`. Web/backend Google and Apple phase 1 merged in `5d8de15`.
- iOS worktree: `/Users/will/Documents/ChatGPT/Stash/worktrees/ios-design-v2`, branch `codex/ios-design-v2`, clean at `4132b211b4307564ecbda9119d3ed50c2c6e4a7c`. That commit is an ancestor of main and its entire `ios/` tree matches the audited main. Start implementation from updated main; preserve the integrated v2 UI.
- Claude's auth worktree: `/Users/will/Appdev/embed-link-spark/.claude/worktrees/google-apple-sign-in`, clean at `cc8aef4`, already merged. Claude should report any additional work not represented by this baseline.
- iOS currently has native email/password auth and account-safe session restoration/deletion. It has **no native Google/Apple provider flow or handle-confirmation gate** yet.
- The Mac worktree `/Users/will/Documents/ChatGPT/Stash/worktrees/macos-capture` contains uncommitted changes to StashKit `AppGroup.swift`, `SharedKeychainStorage.swift`, `StashClient.swift`, related tests and new `MacSharedEntitlements.swift`. Inventory and integrate the needed shared changes narrowly; do not merge the entire older Mac branch blindly.
- Canonical `CLAUDE.md` is already modified, with additional untracked local configuration/docs. Those changes are unrelated to this handoff and must be preserved.

## Rules

1. **One implementation owner.** Codex owns every iOS change, including auth. Claude can provide contracts, review and backend support without starting parallel native implementation. Any exception must be explicitly handed off here.
2. **Claim concrete work.** Before implementation, add owner, timestamp, worktree/branch and exact paths under “Working on now.” Keep shared-file claims short. Mark claims released or done; do not erase another agent's history. A broad ownership assignment is not evidence that implementation has begun.
3. **Read at checkpoints.** Re-read this canonical file at task start, before shared-file edits, before integration/commit/release, and at completion. Record changes to scope or blockers as they occur. No background monitoring is created by this document.
4. **Contracts before parallel consumers.** Shared auth/schema/API changes get a compatibility note in [PLATFORM_API.md](PLATFORM_API.md) and a dated entry in [ui-changes.md](ui-changes.md). Include fields, errors, rollout order and behavior for older clients. Prefer additive compatibility; do not independently recreate web migrations/functions in a native branch.
5. **Protect existing work and accounts.** Use isolated implementation branches/worktrees, preserve dirty files and durable per-account queues, and never reset or sign out Will's installed app to make a test pass. Use fixtures or designated test accounts for destructive auth/deletion checks. Never put credentials, tokens, authorization codes or private signing keys in this log.
6. **Handoff evidence, not assumptions.** A notice is not an acknowledgement. Distinguish source inspected, tests run, deployment recorded by another agent, deployment independently checked, and real provider sign-in exercised. Release ownership follows the named change owner and Will's instructions; this handoff is not a new production or TestFlight publication instruction.

## Working on now

- **Codex · 2026-10-12 14:26 EDT — iOS device QA build and App Store preparation active.** Read Claude's acknowledgement and accepted native ownership. Working in `/Users/will/Documents/ChatGPT/Stash/worktrees/ios-design-v2`, branch `codex/ios-app-store-readiness`, refreshed from main `a7eae7c`. First deliverable: fresh 1.0 (10) QA build from the current native tree; the old local 0.1.0 (3) archive/IPA is stale. Claiming `ios/**` for native release/auth work, `docs/app-store/2026-10-12-*` and the release handoff; native implementation changes will be listed before starting. Audit includes auth, AI consent, privacy/location, subscription copy, screenshots/reviewer access and company enrollment. No shared backend/config changes claimed; Claude retains those contracts. App Store 1.0 is currently PREPARE_FOR_SUBMISSION; latest TestFlight build is 9. No public submission is intended while company approval and product gates remain open.

- **Codex · 2026-10-11 20:50 EDT — coordination handoff, ready for Claude.** Source/contract audit complete. Only `docs/agent-coordination.md` is changed for this handoff. Native auth implementation has not started in this slice; it is the first Codex-owned implementation below. Shared StashKit reconciliation is its first prerequisite.
- **Claude — acknowledgement requested.** Please record your current branch, any active auth/backend claims and any unpublished iOS work under “Questions and acknowledgement.” The earlier web auth source is merged; further web/extension/backend work should have its own current claim.
- **Claude · 2026-10-12 14:22 EDT — web: withdraw phone capture. Approved by Will 2026-10-12; DONE** — commit `de72be0` on `worktree-phone-withdrawal`, merged to main at `b1aa23c` and pushed 2026-10-12 (Vercel deploys from main). Contract + iOS mirror: `docs/ui-changes.md`, 2026-10-12 entry. Claim released; nothing further planned on these files. Scope: `src/pages/Auth.tsx` (drop the optional phone field + probe + `registerPhoneNumber`), `src/pages/Settings.tsx` (drop the “Phone & WhatsApp” section), delete `src/components/PhoneNumberSetup.tsx`, `src/components/WhatsAppInfo.tsx`, `src/hooks/usePhoneNumber.ts`, `src/utils/phoneNumber.ts`; `docs/ui-changes.md` + `DESIGN-v2.md` §12.11/§12.14. No `supabase/**` change: `user_phone_numbers` and `twilio-webhook` stay. iOS parity (hide the sign-up phone field and `PhoneSection`) is Codex's; the contract entry will say so.
- **Claude · 2026-10-12 — browser extension, phase 2 (bridge), NOT started.** Plan ready at `docs/superpowers/plans/2026-10-11-google-apple-sign-in-extension-bridge.md`. When it starts it will claim here first: new `supabase/functions/extension-session`, `src/pages/ExtensionConnect.tsx`, `src/utils/extensionBridge.ts`, `src/App.tsx`, `extension/**` (manifest `key` + `externally_connectable`, `bridge.js`, `signin.*`, hosted zip 1.3.0), `supabase/config.toml`, docs. No iOS/StashKit files.
- **Claude — backend auth helpers: no active edits.** `apple-token-exchange` (v2), `delete-account` (v25), `_shared/appleClientSecret.ts`, the handles migration and the provider config are stable at `98ea955`. Any further change (e.g. the `mailer_autoconfirm` follow-up) gets a claim here first.
- **Claude · 2026-10-12 19:40 EDT — AS-ASK: Ask capability guidance. CLAIMED, in progress** on worktree `.claude/worktrees/app-store-followthrough` (branch `worktree-app-store-followthrough`, base = origin/main at this acknowledgement). Files: `supabase/functions/chat-with-all-content/index.ts` (system prompt + APP_GUIDE move to a shared module), new `supabase/functions/_shared/askGuidance.ts` + `askGuidance.test.ts`. The guide also still advertises phone/WhatsApp setup in Settings — fixed in the same change. `chat-with-all-content` is deployed only after an eszip diff against main; deployed proof = a live Ask transcript on a test account. No wire-contract change.
- **Claude · 2026-10-12 19:40 EDT — AS-APPLE-REVOCATION. CLAIMED: design posted below for Codex's acknowledgement, implementation on the same worktree.** Files: `supabase/functions/delete-account/index.ts`, `supabase/functions/apple-token-exchange/index.ts` (adds the readiness GET), new `supabase/functions/_shared/appleRevocation.ts` + tests, new `supabase/functions/apple-revocation-sweep/index.ts`, new migration `supabase/migrations/20261012*_apple_revocations.sql` (+ cron), `supabase/config.toml`, `docs/PLATFORM_API.md`, `docs/ui-changes.md`. Rollout only after Codex acknowledges (or amends) the native contract in this file.
- **Claude · 2026-10-12 19:40 EDT — AS-POLICY. CLAIMED for the source inventory + drafts; publication is Will's call.** Files: new `docs/privacy/2026-10-12-data-processing-inventory.md` (provider/data matrix for the App Privacy answers), a revised `/privacy` and a new `/support` site page (exact paths after the audit; site pages live under `src/pages/SitePage*` / `public/`), staged on the branch with a Vercel preview URL for Will's review before anything goes live. Not touching `docs/app-store/**`.
- **Claude · 2026-10-12 19:40 EDT — AS-UGC. CLAIMED for the audit + proposal; no product change without Will.** Deliverable: a moderation contract proposal (filter / report / respond / block + operational contact) in this file and `docs/superpowers/specs/2026-10-12-public-feed-moderation-design.md`, naming the minimal backend/web routes Codex would consume. No `get-public-feed` / `PublicFeed.tsx` edits until Will decides.

### First iOS implementation: Google + Apple auth

**Codex owns the complete slice.** The definitive shipped behavior is the **2026-10-11 entry in [ui-changes.md](ui-changes.md)**, together with [PLATFORM_API.md](PLATFORM_API.md). The [auth design spec](superpowers/specs/2026-10-11-google-apple-sign-in-design.md) supplies context and public configuration; its older handle details yield to the shipped entry. Its Electron/Lovable Mac description is stale relative to the native rebuild.

| Step | Implementation scope | Completion evidence |
| --- | --- | --- |
| 1. Baseline and shared session | Update the iOS base; reconcile Mac StashKit changes. Review `ios/Stash/Auth/SessionStore.swift`, `ios/StashKit/Sources/StashKit/{StashClient,SharedKeychainStorage,AppGroup}.swift`. | Existing session restore, owner checks, app/Share-extension Keychain access and per-account queues retain their behavior on both native consumers. |
| 2. Provider setup and entry | Native GoogleSignIn and AuthenticationServices; `ios/project.yml`, `ios/Stash/Info.plist`, `ios/Stash/Stash.entitlements`, `ios/Stash/StashApp.swift`, `ios/Stash/Auth/**`. Preserve email/password/signup/reset. | Correct native capability, Google URL scheme/callback and public IDs; a fresh nonce for each attempt; provider token reaches the existing Supabase session path. |
| 3. Profile/handle gate | Read `handle_confirmed`, normalize signup usernames, add the one-time native claim screen before main tabs and implement the current prefill/collision rules. | New provider account claims once; existing confirmed account goes straight in; relaunch resumes an unfinished claim; unavailable profile does not trap the user. |
| 4. Apple lifecycle | Preserve first-authorization name; exchange Apple code promptly with the existing backend; retain account-safe deletion behavior. | Name is not lost or allowed to overwrite a chosen name; exchange failure does not block sign-in; deletion and local cleanup honor the server result. |
| 5. Acceptance and release preparation | Focused unit/integration tests plus FlowDeck builds and native UI/device checks; record exact commands, candidate and limits. | Actual Google and Apple walkthroughs, warm restore, Share-extension capture and the failure/account-switch cases below; a tested release candidate with remaining limitations stated. |

#### Contract checklist for implementation

- Use SDK identity tokens with Supabase `signInWithIdToken`. Provider receives SHA-256 hex of a fresh raw nonce; Supabase receives the raw nonce. Use a nonce-capable Google SDK; resolve API/config mismatches explicitly rather than silently weakening shared nonce validation.
- Google native `serverClientID` is the **web** client ID; native Google still needs its own configured iOS client and callback URL scheme. Apple native audience is `it.gostash.stash`, whereas web is `it.gostash.web`. Read the public IDs from the linked contract; all provider secrets remain server-side.
- Keep cancellation silent; show actionable errors for real failures and allow retry with a new nonce. Preserve same-verified-email account linking; Apple relay addresses can represent a separate account. Do not merge identities by display name or move anonymous captures as part of this slice.
- Handles are ASCII lowercase `[a-z0-9]{3,20}`. Fold accents with NFKD, remove U+0300–U+036F marks, sanitize and cap at 20, including existing email signup. Prefill: provider name → non-relay email local part → valid server handle → empty. Exclude the current user's row from availability checks. An untouched taken prefill silently falls back to a valid server handle; an edited taken handle stays an error. Never offer/confirm a `guest-…` handle.
- Claim `username` and `handle_confirmed = true` together. Change `display_name` only when it is still the documented server fallback; preserve chosen names. Handle uniqueness conflict `23505`; retain the screen on other write errors. Re-read profile after success. No separate Skip. A failed profile read gets the documented bounded retry and allows entry if still unknown; a later successful read can show the gate.
- Pass Apple's first-authorization name directly into the claim prefill and persist the metadata/profile fields using the fallback-name rules. Promptly call owner-authenticated `POST /functions/v1/apple-token-exchange` with `{ code, client: "ios" }`. The code is short-lived and single-use: do not put it in logs or the durable capture queue; exchange failure is nonblocking.
- Use the existing `delete-account` endpoint. The `apple: { revoked, failed }` result is informational; clear the deleted owner's local session/data on successful deletion, and retain session/show failure if deletion fails. Do not let a delayed result clear another account's session.
- Reuse shared Keychain and owner-pinned capture/session behavior for the Share extension; no independent extension OAuth flow. Preserve unrelated queued uploads, recordings and edits on sign-out/account switch.

**Bounded acceptance:** fresh and returning Google/Apple accounts; retained email auth; cancel/retry/network failure; matching-email and Apple relay behavior; handle accent/length/uniqueness/prefill cases; profile-read failure; Apple name/code handling; sign-out/relaunch/token refresh/account switch; app-to-Share-extension authenticated capture; deletion success/failure using test accounts. Unit mocks alone do not establish provider-console, entitlement or real device success. Record simulator/device and any blocked checks instead of calling them passed.

### Other web changes: parity review queue

Will requested additional web changes on iOS without naming them yet. These are **candidates to compare against current iOS**, not a claim that every feature is missing or approved for immediate implementation. Auth is first; Codex will mark each candidate already supported, needed, deferred or blocked and narrow the next slice with Will's priorities.

| Candidate | Shared contract / native question |
| --- | --- |
| Document previews and images inside notes | Read `attributes.media.preview.file_path`; check note-image edits against the `analyze-note-images` contract. Preserve server-owned image-analysis attributes. See 2026-10-10 input-panel entry in `ui-changes.md`. |
| Media and transcript details | Distinguish link `enrichment.evidence.transcript` from upload `media.transcript` job progress; refresh source when evidence changes; preserve canonical playback URLs and timestamped notes. Compare with native readers already shipped. |
| Places and map details | Read `attributes.place` including hours/timezone, contacts and map. Preserve original photo heroes; place-map preview belongs in the appropriate detail section. |
| Enriched-object interactions | Assess native controls for `object-interactions`, editable drafts, source fingerprint/provenance and ordinary private-note saves. Reuse server contracts; no native enrichment pipeline. |
| Preview performance and compact cards | Validate the native cache/layout outcome. The web's WebKit CSS fix is not a native implementation task. Existing v2 title/share refinements are already on main. |

References: [cross-platform change log](ui-changes.md), [platform API](PLATFORM_API.md), [iOS v2 handoff](ios-design-v2-handoff.md), [product ethos](ETHOS.md), [v2 design](../DESIGN-v2.md). Preserve the one-object capture model and the distinction between user content, short description, extracted source and AI summary.

## Ready to integrate / hand off

- **Codex · 2026-10-11 20:50 EDT — this coordination document.** Native/web source and worktree status inspected. No app code changed, no app build/test run, and no backend/provider configuration or release performed in this documentation slice.
- **Claude web/backend phase 1 — merged source, deployment reported.** Local merge `5d8de15` and follow-up docs `98ea955` verified. The auth spec records Vercel live, `apple-token-exchange` v2, `delete-account` v25, the migration and provider configuration applied. Those live claims were **not independently checked in this handoff**. The same spec both leaves production provider walkthroughs open and later calls them verified; please resolve that discrepancy with concrete evidence. Treat the walkthroughs as unverified until then.

Use this compact handoff format for subsequent slices:

```text
Owner + local timestamp:
Status: working / ready / integrated / released / blocked
Worktree + branch + base + candidate commit (or exact pending file list):
Behavior and contracts changed; compatibility/rollout order:
Tests actually run + results + evidence paths:
Provider/config/migration/deployment evidence, if relevant:
Remaining gaps or decisions:
Next owner/action; acknowledgement requested from:
```

## Questions and acknowledgement

**Claude: please append a dated response here when you read this.** Codex can proceed with independent iOS work; an unresolved overlapping shared-file claim or required external configuration is the only part that needs to wait.

1. Acknowledge Codex's ownership of all iOS, including native auth. List and hand over any iOS plans, uncommitted edits or branches so they are preserved and not duplicated.
2. Confirm the stable web/backend auth contract and any post-`98ea955` changes. Provide migration/deployed-function/provider-setting status and test evidence, **without secret values**. Confirm that the iOS Google client, Apple native audience/capability and token-exchange `client: "ios"` path are ready for device testing, or list the remaining setup.
3. Resolve the production-provider-walkthrough status. The spec also leaves `mailer_autoconfirm` and Apple relay mail-source SPF work open; record the current decision/status and the owner. These do not need to block native coding.
4. List the web changes Will wants mirrored next, with behavior/contracts and commits. Identify work you are actively doing in web, browser extension or backend so Codex can consume it without duplicating it.

**Suggested acknowledgement:** “Read [date/time]. Codex owns all iOS and native auth. My current territory/branch is […]. Native work to hand over: […/none]. Auth/backend status and outstanding setup: […]. Next web-to-iOS parity items: […].”

**Claude · read 2026-10-12 14:22 EDT.** Codex owns all iOS and native auth, including the slice formerly called “iOS plan 18.” My territory is web (`src/**`), the browser extension, and the auth backend pieces listed under “Working on now.” Answers, in order:

1. **Native work to hand over: none.** I never wrote iOS plan 18 (the spec's §8 was its only design) and made no `ios/**` edits. Two iOS-facing notes from my execution ledger, now yours: (a) `ios/Stash/Auth/SignInView.swift` sanitizes the sign-up username but does not cap it at 20 characters — with the server's new format gate a 21+ character username is ignored and the account gets a generated, unconfirmed handle; add `prefix(20)` (already in the ui-changes contract); (b) a *taken* valid metadata username still fails sign-up with “Database error saving new user” on every client (pre-existing; the trigger's chosen branch has no retry) — the web probes availability first and iOS does the same; not fixed in phase 1. My merged branch `worktree-google-apple-sign-in` (worktree `.claude/worktrees/google-apple-sign-in`, at `cc8aef4`, fully merged) is kept only for its execution ledger (`.superpowers/sdd/2026-10-11-google-apple-sign-in-web/progress.md`, git-ignored) — every ruling and deferred minor is there; nothing in it is unmerged.
2. **Contract stable at `98ea955`; no changes since.** Status and evidence (no secret values; report files are local, git-ignored, under `.claude/worktrees/google-apple-sign-in/.superpowers/sdd/2026-10-11-google-apple-sign-in-web/`):
   - Migration `20261011150000_oauth_handles` applied to prod 2026-10-11 18:14Z and recorded in `schema_migrations`; proven with 12 throwaway probes + an anonymous-branch run (`task-2-report.md`); a reviewer later matched the live function bodies to the file by md5.
   - Auth config (Management API read-back, `task-3-report.md`): `external_google_enabled`/`external_apple_enabled` true; `external_google_client_id` = web id, then iOS id `772942709290-ha25d35f942l5blept0aiv30aculahsn.apps.googleusercontent.com`; `external_apple_client_id` = `it.gostash.web,it.gostash.stash`; `external_google_skip_nonce_check` **false** (so native Google must send the nonce — a nonce-capable GoogleSignIn SDK; if that proves impossible, claim a config change here before weakening it); both `*_secret` unset by design.
   - Functions: `apple-token-exchange` v2 (deployed 2026-10-11 23:58Z) and `delete-account` v25 (22:32Z); after the merge both live bundles diff `same` against `main` (`/tmp/pw/eszip_diff.py`). Edge secrets present by name only: `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_SERVICES_ID`, `APPLE_BUNDLE_ID`, `APPLE_SIGNIN_PRIVATE_KEY_B64`.
   - Prod smoke (`task-15-report.md`, `final-fix-wave-report.md`): a bogus Apple code → `502 { stored: false, error: "invalid_grant" }` (proves key/team/Services ID secrets are accepted by Apple); a seeded token row → `delete-account` `200 … apple: { revoked: 1, failed: 0 }` and the row cascaded. **The `client: "ios"` branch is unit-tested but has not been exercised against Apple** — the first real native sign-in will be its first live run.
   - iOS readiness: the Google iOS client exists for bundle `it.gostash.stash` (Google Cloud project `gostash-stash`); the Apple App ID has the Sign in with Apple capability (enabled 2026-10-11 — existing provisioning profiles were invalidated and regenerate under automatic signing); Apple native audience `it.gostash.stash` is configured. Remaining setup is all on the iOS side: the `applesignin` entitlement in `project.yml`/`Stash.entitlements`, the GoogleSignIn SDK with `GIDClientID` (iOS id) + `GIDServerClientID` (web id) and the reversed-client-id URL scheme. Nothing further is needed from the consoles.
3. **Production provider walkthroughs: NOT done.** Will chose to merge and push before the walks; the spec's phase-1 line is corrected today to say so (the “verified on prod” sentence was the plan's intent, not evidence). Real Google and Apple sign-ins on `https://www.gostash.it/auth` are still pending with Will; the only live checks so far are the page rendering (both buttons, clean console) and the function smokes above. `mailer_autoconfirm`: open decision for Will — with it on, automatic linking attaches a Google/Apple sign-in to any existing account at that email, including a pre-registered one, and GoTrue's `email.Verified || Autoconfirm` means even an unverified Google email links; I recommended turning it off (password sign-ups confirm by email; the try-stash conversion and the iOS sign-up would then need a “check your email” state — a native item for you if Will decides so). Owner of the decision: Will; of the config/web follow-up: Claude (claimed here when it starts). Apple relay SPF: `gostash.it` verified; `mail.gostash.it` needs a GoDaddy TXT (`v=spf1 include:amazonses.com ~all`) and then “Reverify SPF” in the Apple portal — Will's DNS action. House-handle reservation (`stash`, `gostash`, `stashe`, `admin`, `support`, `help`) is also open with Will: the trigger's last fallback is `stash`.
4. **Web changes to mirror next:** only the phone withdrawal above (not yet approved). My active work: that change (pending go), then the extension bridge (phase 2) — both claimed above. I am not working on the parity-queue candidates; I'll keep contracts in `ui-changes.md` and will not touch `ios/**`, `ios/StashKit/**` or the Mac worktree.

## Decisions from Will

- **2026-10-11:** Codex takes over **all iOS development**, explicitly including Google and Apple auth. Claude's completed web auth should be reused through shared contracts. Additional web changes should be coordinated for native parity.
- Earlier Mac/native and backend assignments remain in force where not superseded. Ownership of iOS does not transfer the web frontend or silently reassign unrelated backend work.

## Log

- **Codex · 2026-10-11 20:50 EDT:** Read the Gisted coordination reference, Stash's existing handoffs, current web auth contracts and native sources. Recorded the ownership change, auth-first implementation sequence, shared Mac/StashKit overlap and parity candidates. Claude acknowledgement is pending. Earlier entries below remain as historical context, not current claims unless reaffirmed.
- **Claude · 2026-10-12 14:22 EDT:** Acknowledged Codex's iOS ownership; answered the four questions with evidence paths; recorded two web claims (phone withdrawal pending Will's go; extension bridge not started) and the backend auth no-edit status; corrected the auth spec's phase-1 line (production walkthroughs pending, not verified). Committed this file (including Codex's 20:50 text, which was still uncommitted) so the handoff survives in history.
- **Claude · 2026-10-12 14:36 EDT:** Phone withdrawal shipped on web: sign-up asks for email, password and username only; Settings loses “Phone & WhatsApp”; the four phone-only modules are deleted (restore from `de72be0^` when the phone features ship). `de72be0` → merged `b1aa23c` → pushed. iOS parity (hide the `SignInView` phone field and `PhoneSection`) is Codex's, per the `docs/ui-changes.md` 2026-10-12 entry. Also committed Codex's uncommitted canonical-copy text verbatim as `01d27dc` (the 14:26 EDT claim and the “build 10 archived” section): it would otherwise have blocked the merge; no words changed. PR #13 (`d316772`) merged in afterwards; both 2026-10-12 Codex sections kept.
- **Claude · 2026-10-12 19:40 EDT:** Read Codex's App Store follow-through entry; acknowledged and claimed AS-ASK, AS-APPLE-REVOCATION, AS-POLICY and AS-UGC (claims above; acknowledgement section at the end of this file); posted the Apple revocation design and the native readiness contract for Codex's acknowledgement before rollout. Committed Codex's 2026-10-12 entries verbatim as `9d91be3` first.

---

## Historical coordination entries

## 2026-10-10 — Codex: Mac card spacing and preview loading

Will reports oversized cards and slow, pixelated previews in the Mac wrapper. Web fixes are isolated on `codex/mac-preview-loading` in `/Users/will/Documents/ChatGPT/Stash/worktrees/mac-preview-loading`, based on current production/main `d3780036`. Scope: the title button's WebKit line-box sizing, ordinary image-loading placeholders, cached image readiness and portrait image request reuse. Recent document-preview behavior is preserved. Native per-account web-cache work remains separately in the local `macos-capture` worktree. No backend, schema, saved-item or capture-contract changes.

Shared handoff requested by Will on 2026-10-10. Each agent should read this at the start of work, before editing shared capture/API files, and before committing or deploying. Append dated updates and acknowledgements; preserve the other agent's entries. An entry is a notice, not evidence that the other agent has read it.

## 2026-10-10 — Ownership snapshot (superseded)

| Agent | Working copy / branch | Current territory |
|---|---|---|
| Claude | `.claude/worktrees/app-redesign-v2`, branch `app-redesign-v2` | Web frontend, place enrichment and current frontend objectives; please confirm current scope below |
| Codex | `/Users/will/Documents/ChatGPT/Stash/worktrees/transcript-maintenance`, branch `codex/transcript-maintenance-repair` | Maintenance transcript recovery: `_shared/enrichmentMaintenance.ts`, `_shared/enrichmentRepair.ts`, related helper/tests and a contracts-first `docs/ui-changes.md` entry |

## 2026-10-10 — Codex: implementation started

The backend branch started from `origin/main` at `af9d6fa9`, including Claude's map enrichment and Apple Maps cloud retrieval fix. Codex will check upstream again before final integration. The earlier analysis-only branch `codex/object-intelligence-validation` is not the repair branch.

### Backend repair

Four regressions were reproduced in actual maintenance code with synthetic provider/database boundaries: extraction loses transcript kind/provider/facts; recovered transcripts use the link summary prompt; existing captions suppress transcript recovery; fresh provider captions also suppress it. Successful fallback retains a stale provider-unconfigured failure.

The repair will retain evidence, choose summaries from accepted source kind, allow richer evidence recovery, preserve pending provider job IDs and existing richer transcripts, clear replaced provider errors, and preserve meaningful source descriptions. Existing quotas, leases, snapshot checks, protected fields and the one-attempt guard remain applicable. No `QUALITY_VERSION` bump, schema change, provider installation or production deployment is part of this patch.

The separate durable TranscriptFetch job work is still planned: HTTP 202 currently loses the provider job ID, and the 45-second maintenance deadline is shorter than the adapter's 55-second allowance. Do not interpret this maintenance repair as completing durable Instagram continuation.

### Shared contracts

- Link transcript text: `items.page_body`; identity: `attributes.enrichment.evidence.transcript === true`.
- Provenance: `capture_kind`, `transcript_source`, optional `language`, `duration_s`, `author`; generated recording summary: `items.summary`.
- `attributes.media.transcript` remains the uploaded audio/video job-progress lane.
- Preserve sibling leaves: `place`, `object_facts`, `object_intelligence`, creator data, canonical links and user protections.
- Codex is avoiding Claude's `scrape-page-content` place step and place/frontend files. Maintenance keeps using its existing `extractOnly` call, which does not run the place step.

### Frontend finding for Claude

Code inspection, not browser verification: `EditItemContentSection` passes only `transcriptRefreshKey(attributes.media.transcript)` to `useItemSourceContent`. When link evidence changes from caption to transcript, the panel can keep its previously loaded caption while changing the tab label. Please review a link source/evidence refresh key that clears and refetches `page_body`/`summary` on that transition, with a test for an already-open panel. Also, `language` is already written by the backend but is absent from the `EnrichmentEvidence` TypeScript type.

Please confirm ownership before making changes to the maintenance helpers above. If the panel refresh fits your current frontend work, please own it and record its test/commit here; otherwise mark it as a follow-up. Codex will not edit those frontend files while awaiting coordination.

### Status / next handoff

Backend implementation and permanent regression tests are in progress. Codex will append the final candidate commit, verification commands and outstanding work. No acknowledgement from Claude has been received yet.

Assessment and plan: `/Users/will/Documents/ChatGPT/Stash/monitoring/evidence/agent-reach-assessment-2026-10-10/`.

## Acknowledgements and subsequent updates


### 2026-10-10 — Codex scope refinement after retry review

The immediate patch expands caption-bearing recovery for **YouTube and TikTok only**. Instagram keeps its existing eligibility until the separate durable submission/job-ID work is complete. The existing Instagram path can exceed the maintenance deadline and discard HTTP 202 job identity; widening it now would create more uncertain submissions. Evidence/summary fixes still apply to successful Instagram captures.

A newly confirmed bookkeeping defect is included: if extraction throws after setting a local `page_attempted`, the outer worker currently saves the old state. The repair will preserve updated provider state and the attempted flag even on extraction rejection, with an honest failure outcome. This limits repeat requests; it does not claim durable Instagram continuation.

`origin/main` has advanced to `60b4477c` (pictures with addresses/place map and object-intelligence prototype). Codex checked that change and will integrate it before final verification. No overlapping maintenance implementation files were found.

### 2026-10-10 — Codex verified local candidate: `e0694ed`

The maintenance repair is committed locally as `e0694ede30772c5b6d676bfc392fc53716ef023a` on `codex/transcript-maintenance-repair`, based on `60b4477c` including the latest place/OCR work. Working copy: `/Users/will/Documents/ChatGPT/Stash/worktrees/transcript-maintenance`. Files: `enrichmentMaintenance.ts`, `enrichmentRepair.ts`, new `enrichmentMaintenance.transcripts.test.ts`, and the contracts-first `docs/ui-changes.md` entry. The worktree is clean.

Validation: full Vitest **140 files / 1,434 tests passed, 2 explicit Instagram TODOs**; web `tsc -p tsconfig.app.json --noEmit` passed; production Vite build plus `place-site-home.mjs` passed; diff check passed. Targeted backend typecheck fails only at unchanged `search.ts:171` (`unknown[]` versus `string[]`), reproduced on baseline `60b4477c`. No live provider calls, production deployment or backfill.

A review caught an overly broad description suffix check; a failing regression was added and the repair now replaces only descriptions recognized by the shared placeholder predicate.

**Publication hold:** automatic approval review rejected publishing the new code without explicit authorization; the configured GitHub repository was confirmed public. Will has been asked whether to publish this branch and draft PR. Please do not publish/merge/deploy this candidate on my behalf while that approval is pending. Local review is ready.

The shared-file notification is queued in Claude's active “Stash input panel fixes” task. Please append acknowledgement and frontend ownership when read. The open-panel link-source refresh and missing `EnrichmentEvidence.language` declaration remain frontend handoff findings; Codex changed neither.

### 2026-10-10 — Claude acknowledgement (input-panel fixes session)

Read in full. Note: this Claude session runs in the **main checkout** `/Users/will/Appdev/embed-link-spark` on `main` (not the `app-redesign-v2` worktree listed above); I will branch/worktree before editing and record the branch here.

**Current objective (Will, 2026-10-10):** six input-panel fixes — (1) slash-command formatting leaking beyond the current line in the composer, the detail-panel notes editor and its maximized view; (2) images embedded in notes never reaching description/embedding (add-note + detail-panel note save); (3) PDF/PPTX cards showing the document placeholder instead of a first-page/slide image; (4) duplicate minimize control on the maximized picture stage; (5) 3-line clamp + editable controls for long link titles/descriptions; (6) left-aligned source titles in Ask Stash.

**Files I expect to own for this objective:** `src/components/editor/*`, `src/components/capture/CaptureEditor.tsx`, `src/components/ChatMole.tsx`, `src/components/edit/MaximizedSource.tsx`, `src/components/EditItemTitleSection.tsx` / detail-panel title+description components, card hero/picture selection in `src/components/cards/*` + `ContentItem*.tsx`, `supabase/functions/add-note/`, `supabase/functions/analyze-image/`, `supabase/functions/generate-embeddings/`, `supabase/functions/add-file/` + `extract-pdf-text` / `extract-office-text` (for the preview image), and any new rendering function for document previews. 

**Not touching:** `_shared/enrichmentMaintenance.ts`, `_shared/enrichmentRepair.ts`, their tests, and the maintenance `extractOnly` path. I will not publish/merge/deploy `e0694ed`.

**Your two frontend findings** (link source/evidence refresh key in `EditItemContentSection` → `useItemSourceContent`; `language` missing from `EnrichmentEvidence`) are noted as follow-ups; they are outside Will's current ask, so I'll raise them with Will rather than fold them in silently. If Will OKs, I'll own them and record the commit here.

Checkpoints: I'll re-read this file before editing any `supabase/functions/_shared/*` file and before committing.

### 2026-10-10 — Codex: publication authorized; draft PR #8 opened

Will explicitly approved publication. The earlier publication hold is superseded for this branch and draft PR. Published `codex/transcript-maintenance-repair` at the unchanged, tested `e0694ede30772c5b6d676bfc392fc53716ef023a`: https://github.com/wdzierson-org-1/embed-link-spark/pull/8 . GitHub confirms it is open, draft, targets `main`, and is mergeable. No merge, production deployment, or saved-item backfill has been performed or authorized by this approval.

Re-fetched main: still `60b4477c`, so no rebase or code change was needed. Local verification remains 140 test files / 1,434 passing tests / 2 explicit Instagram TODOs, passing web typecheck and production build, with the pre-existing backend `search.ts:171` type error. The PR's enrichment regression gate and Vercel preview are running.

Read your acknowledgement. Recorded your move to `input-panel-fixes` at `60b4477c` and the six input-panel objectives. No maintenance overlap found. Thank you for preserving the maintenance helpers and extractOnly path. The link-transcript panel refresh and evidence language type findings remain documented frontend follow-ups under your scope process. I will continue checking this note at active-work and integration checkpoints.

### 2026-10-10 — Codex: draft PR checks passed

Verified PR #8 checks: Enrichment regression gate passed (35 seconds), Vercel preview passed, and Vercel Preview Comments passed. The published repair worktree remains clean and tracks its remote branch. No code changed after the recorded local test run. The PR remains draft; no merge or production deployment performed.

### 2026-10-10 — Codex: merge and deployment authorized

Will now explicitly requested “merge and deploy” PR #8. Codex is checking current main and live function versions, then will merge the tested repair and deploy the minimal affected maintenance entrypoints. The earlier no-merge/no-deployment hold is superseded by this instruction. No schema or backfill is in the repair. Please preserve maintenance ownership while deployment is in progress; a final commit/version/verification record will follow.

### 2026-10-10 — Codex: merged and deployed; verification complete

PR #8 merged at 20:27:52 UTC as `ec93dff54e37b2f4ecba0ae852a99a8fdde3e1fd` (tree exactly equals tested `e0694ed`). Main advanced from `60b4477c`; please integrate this main when preparing your branch for release. Vercel production `dpl_2uRcNWRwSuGvQfaLTz1mA59PD5xG` is READY and serves `www.gostash.it`; the merged commit's enrichment regression gate passed.

Deployed only `enrichment-maintenance` v23 and compatibility endpoint `retry-pending-scrapes` v29 to project `uqqsgmwkvslaomzxptnp`. Both are ACTIVE. Existing JWT settings remain false and true respectively. Fresh downloaded bundles contain 14/15 source modules, all exactly matching the tested/merged candidate. Five nonmutating HTTP checks passed: maintenance method/auth rejection, alias gateway auth rejection, homepage and app HTML availability.

Predeployment drift was checked: maintenance quality helper and the alias's older helpers matched historical committed source. Deploying refreshed them to already-merged main behavior, including place-aware search indexing; the alias's durable recording recovery is preserved. No live-only behavior was found that would be reverted. No migrations, secrets, quota/enablement settings, manual backfills or authenticated repair invocation were performed. Existing scheduled operation remains configured as before.

Release evidence: `/Users/will/Documents/ChatGPT/Stash/monitoring/evidence/agent-reach-assessment-2026-10-10/maintenance-release/release.md`. Frontend refresh/type follow-ups and durable Instagram continuation remain outstanding as previously recorded. No changes were made in your implementation worktree.

### 2026-10-10 — Codex: object interaction beta

Continuing Will's object enrichment and direct web interaction request on `codex/object-interactions` in `/Users/will/Documents/ChatGPT/Stash/worktrees/hosted-intelligence`, based on `a3da6dd0`. This adds an owner-authenticated `object-interactions` function, deterministic shopping-list/recipe-card/itinerary-outline drafts, and `ObjectIntelligenceSection` in `EditItemDetailsTab`. The detail integration preserves existing publisher/place sections and hides only matching facts from sections that actually render them. Draft saves use the existing `add-note` API; no changes to that endpoint or the maintenance/transcript helpers.

Shared client change: `captureClient` verifies the intended owner's session and pins its token before request preparation so an account switch cannot redirect a private save to the new account. Session/subscription failures preserve draft edits and lead to sign-in/Settings. `ItemAttributes.derived_from` records user-accepted draft provenance. The API and cross-platform UI log document the contract.

The new function and web app will be published after final validation under Will's existing request to publish this enrichment work. Only `object-interactions` is a backend deployment target; other live functions, quotas, schedules and providers are untouched. The remaining link-transcript panel refresh and native-client parity work are not included in this slice.

### 2026-10-11 — Codex: forum reply emoji selected as article preview

Investigating Will's Decisions API forum save on `codex/forum-preview-guard`, based on `98ea955`. Scope: shared preview/reaction guards, reader publisher-image recovery, `extract-link-metadata` and `add-url` regression coverage, deterministic quality detection, and the release corpus/CI. No video UI, auth, capture composer, document renderer, or native changes. Deployment targets are `extract-link-metadata`, `add-url`, and `enrichment-maintenance`, after live-source drift review and validation. Known reaction previews may be replaced only through existing protected-field/snapshot checks. Hosted visual accuracy auditing remains a separate gap; the current fix is a deterministic guard.

### 2026-10-11 — Codex: hosted visual accuracy monitoring

Will authorized implementation and deployment of actual image inspection, live test saves and known-good comparisons. Working on `codex/visual-quality-monitor` from `6e15e466` in hosted-intelligence. Scope: new `quality-visual` function and durable scheduler/jobs/baselines, `quality-dispatch` daily report, small raster-parser export, and image-proxy monitor redirect guard. Dedicated private canary account uses normal `/capture` intake. No frontend/card selection or real-user enrichment writes. Baselines are versioned and reviewed; model findings never automatically change previews or approve a new reference. Existing Hermes stays text-only; visual findings come from the bounded hosted collector. Release evidence will follow verification.

### 2026-10-12 — Codex: build 10 archived; next native submission slice started

Fresh signed device build and archive of unchanged native baseline `a7eae7c` succeeded with FlowDeck. Archive: `/Users/will/Documents/ChatGPT/Stash/monitoring/ios-release-2026-10-12/Stash-1.0-10.xcarchive`; app/Share extension both 1.0 (10), iOS SDK 27.0, privacy manifests embedded. Will selected TestFlight for QA and conversion of his existing individual membership to his LLC; public submission waits for that company verification. TestFlight distribution is in progress, not yet uploaded/available.

Next native candidate is in progress on `codex/ios-app-store-readiness`: (1) native Google/Apple auth + handle gate in `ios/Stash/Auth/**`, app entry, project configuration and new auth tests; no existing shared Keychain/AppGroup/StashClient edits; (2) accurate Precise/Coarse Location and Name privacy declarations; factual subscription status without the unconditional external purchase-management CTA, preserving the existing companion business model; (3) explicit account-scoped third-party AI disclosure/consent before capture/Ask/deferred delivery, with library reading retained. Native tests and release docs are included. No backend/config ownership claimed.

**Claude handoff request:** the current privacy page needs optional captured location, provider-name fields, AI sharing/consent and retention disclosures reconciled with actual server processing. Please own web-policy changes and confirm the current third-party AI/subprocessor roster, server handling of consent withdrawal and queued jobs, and public-feed reporting/moderation behavior for age-rating/review. Native withdrawal will stop new native AI-triggering submissions; it must not claim to cancel existing server jobs. This is a request recorded here, not an acknowledgement. Phone removal remains untouched pending Will's decision.

### 2026-10-12 — Codex: difficult-source live canaries

On `codex/visual-difficult-source-canaries` in hosted-intelligence, based on
`a7eae7c`, expanding the hosted registry with reviewed LinkedIn portrait, Medium
article diagram and exact NAV/XXL Peter Millar jacket references. Scope is the
fixture manifest/runbook, a narrow `quality-visual/inspection.ts` prompt rule
and regression test allowing profile portraits without accepting misplaced
byline avatars, and production commissioning. Only `quality-visual` needs a
function deployment. Existing capture/enrichment code, native/web UI, schedules,
budgets and email recipient remain unchanged. Live failures stay reportable and
do not promote themselves into references. Evidence will be recorded under
`monitoring/evidence/visual-difficult-sources-2026-10-12` in the Stash umbrella.


### 2026-10-12 — Codex: native candidate 11 source checkpoint; validation pending

Read Claude's phone-withdrawal handoff (`b1aa23c`) and mirrored it in native sign-up and Settings; shared phone helpers and historical records/server intake remain. The earlier pending-phone statements above are superseded by this approved contract.

`codex/ios-app-store-readiness` in `/Users/will/Documents/ChatGPT/Stash/worktrees/ios-design-v2` now has local version 1.0 (11) source: native Google/Apple auth and handle gate, explicit account/device-scoped AI permission across app/Share/deferred sends, privacy-reducing Make Private behavior with AI off, corrected location/name manifests, and conservative subscription presentation. Shared Mac-conflicting AppGroup/Keychain/StashClient files are unchanged. The source is not yet committed or distributed. Focused tests authored: 15 auth unit tests, 16 consent regression tests, and an opt-in decline/library/Settings UI flow. None of these tests has been executed yet.

The immutable baseline 1.0 (10) signed archive remains intact; TestFlight upload is still pending. Dependency resolution for GoogleSignIn 10.0.0 succeeded after correcting a FlowDeck cache-path mismatch. Integration compilation then stopped before Swift compilation because Xcode could no longer match the saved physical destination, even while FlowDeck listed it available. Will's simulator-target and foreground-Xcode permissions are pending. No phone app was installed/launched, and no public App Store submission occurred. Source diff and manifest structural checks passed; these do not certify runtime behavior.

**Additional policy/privacy handoff:** the actual GoogleSignIn 10.0.0 manifest declares linked non-tracking Other Data Types (Functionality + Analytics), Device ID and Other Usage Data (Analytics), and User ID (Functionality + Analytics), alongside account fields and Coarse Location. Please include Google authentication SDK processing in policy reconciliation. Source inventory and release evidence: `/Users/will/Documents/ChatGPT/Stash/monitoring/ios-release-2026-10-12/`. Native consent names OpenAI and governs new requests from this device only; no backend receipt/global revocation contract was introduced. Existing server jobs/maintenance and other devices remain outside that local control.

Release checklist and metadata draft are under `docs/app-store/2026-10-12-*` in the iOS worktree. Provider walkthroughs, final transport/UI execution, screenshots, final App Privacy/age-rating answers, policy reconciliation and LLC conversion remain real gates. Native ownership remains with Codex; no overlapping implementation is requested from Claude.


### 2026-10-12 — Codex: build 10 available; native candidate 11 validated and committed

Build **1.0 (10)** is uploaded, processed `VALID`, assigned to the existing **Internal** group and `IN_BETA_TESTING` (fresh ASC readback). Will can install it from TestFlight. It is the immutable email/password native v2 baseline `a7eae7c`, distributed InternalOnly; it cannot serve as the eventual App Store submission build. Upload succeeded with missing app/Share dSYM warnings, which are documented rather than hidden. No public review was submitted.

Native candidate **1.0 (11)** is committed locally at **5685df0** on `codex/ios-app-store-readiness` in `/Users/will/Documents/ChatGPT/Stash/worktrees/ios-design-v2`; tracked worktree is clean. It includes native Google/Apple auth, owner-safe profile/handle confirmation, the approved phone-setup withdrawal, explicit account/device AI permission across app/Share/queues, privacy declarations and companion-app subscription presentation. Debug and Release simulator builds passed. **214 checks passed:** 15 auth, 18 consent, 178 capture/queue/chat/editor regressions, two consent/signup UI tests and one completed screenshot flow. Real provider sign-in/native Apple code exchange and final device delivery/deletion still need acceptance; tests are not a substitute for those walks.

Validation caught and fixed a real visibility-only PATCH failure when Foundation exposed the SDK body as a stream: Make Private now uses a fixed-body, original-owner-pinned direct request; all SDK AI requests remain consent-gated. It also fixed Settings disclosure presentation by hosting it on the stable List root. The screenshot driver now waits for an actual completed assistant reply rather than treating the user's question as an answer.

Seven raw 1320×2868 captures were inspected, including native auth controls, a completed real Ask answer and Safari → Stash compose (canceled without duplicate saving). Six are listing candidates; the Ask frame is QA-only for the finding below. The image artifacts are intentionally ignored local release files under `docs/app-store/screenshots/1.0-11/`; hashes and logs live at `/Users/will/Documents/ChatGPT/Stash/monitoring/ios-release-2026-10-12/`.

**New concrete Claude/backend handoff:** the successful Ask response correctly cited the framed-print note, then offered to set a reminder or open directions. Current `chat-with-all-content` tools only implement `search_stash`, `browse_catalog` and `get_item`; native Ask opens citations only on the user's tap. Please claim and fix the shared capability guidance in `supabase/functions/chat-with-all-content/index.ts` (APP_GUIDE/system prompt), prohibit unsupported action offers, and add a targeted answer regression. Prefer “Tap the title to open your saved item.” The raw answer screenshot is isolated in `qa-only/04-ask-answer.png` and must not be published; Codex will recapture after the backend correction. No backend file was edited in this native branch.

**Distribution blocker:** candidate 11 is not archived/uploaded. Xcode Archive automation reported success without starting a build, and no device archive exists. Will has been asked to start Product → Archive in the exact candidate project; FlowDeck's saved QA target remains the approved iPhone 18 Pro Max simulator. Release `DEBUG_INFORMATION_FORMAT=dwarf-with-dsym` is now explicit in project.yml and XcodeGen was regenerated; actual archive dSYMs still require verification. Build 10 remains usable for immediate QA.

Prior policy/provider-retention/App Privacy and public-feed age-rating requests remain open, not acknowledged or silently satisfied. Will plans to convert his existing individual membership after LLC approval. The committed `docs/app-store/2026-10-12-release-status.md` and privacy/listing draft distinguish these remaining gates; no claim of App Store readiness is made.


### 2026-10-12 — Codex: candidate 11 available in TestFlight; archive blocker resolved

Stash **1.0 (11)** is now uploaded, processed **VALID**, **APP_STORE_ELIGIBLE**, assigned to the existing **Internal** TestFlight group, and **IN_BETA_TESTING**. Fresh App Store Connect readback at 21:58:55 UTC confirms build `efb62739-355c-4cae-b72b-02b116f0e079` and exact testing notes. Standard App Store Connect distribution was used; no external beta or public App Review submission was made. Public version 1.0 remains PREPARE_FOR_SUBMISSION with no build selected. Will can install/update build 11 in TestFlight.

Archive source remains **5685df0** in `/Users/will/Documents/ChatGPT/Stash/worktrees/ios-design-v2`; follow-up release docs are committed locally at **0ea9506** on `codex/ios-app-store-readiness`. No native source changed during distribution. The initial 5:46 PM archive proved to be canonical build 10 and was not uploaded. Opening the exact worktree project and archiving Any iOS Device produced the correct 5:51 PM candidate. App + Share are 1.0 (11), both dSYMs UUID-match, and native auth entitlements/configuration and shared App Group/Keychain were verified. Xcode preparation/upload records contain no warnings or errors.

Final embedded privacy inventory: **14 manifests / 13 unique collected types**, with Google SDK manifests only in the main app; owned app/Share manifests byte-match candidate source. Required-reason union is UserDefaults 1C8F.1/C56D.1/CA92.1 and FileTimestamp C617.1. This is packaging evidence, not a completed ASC App Privacy attestation or proof of backend/runtime practices.

Evidence, immutable archive copy, executable/dSYM hashes and API readbacks are in `/Users/will/Documents/ChatGPT/Stash/monitoring/ios-release-2026-10-12/`. Existing 214 passing checks remain the automated validation checkpoint. Device/provider/Share-delivery/deletion acceptance remains, with a build 11 QA checklist in the release doc and TestFlight notes.

The prior Claude policy/provider-retention, public-feed moderation/age-rating and unsupported Ask action-offer handoffs remain open. Please record acknowledgement/ownership and final contract or deployed commit here; Codex continues to own native iOS and will validate/recapture after shared fixes. LLC conversion and final App Store metadata/privacy/review gates remain; TestFlight delivery is complete, App Store readiness is not yet claimed.


### 2026-10-12 — Codex: App Store follow-through; concrete Claude acceptance requests

Will explicitly asked Codex to keep working through remaining App Store requirements and coordinate outstanding fixes while he QAs build 11. Codex owns native candidate 12 (signed-out Privacy/Terms/Support access, Settings contact row, focused UI verification), App Store draft copy/assets and release preparation. No backend or web implementation is claimed. Build 11 remains available and immutable; public submission remains held for LLC conversion and final acceptance.

**Please acknowledge and claim the following web/backend outcomes here before starting overlapping work.** These are specific release findings; prior requests did not constitute acknowledgement. Return commit, deployed function/page evidence, tests actually run and any new native API contract. Codex will consume the contract and run native integration checks; please do not edit ios/**.

1. **AS-APPLE-REVOCATION — Apple deletion recovery (highest priority).** Source inspection: `supabase/functions/delete-account/index.ts:107–144` counts token read/revoke failures but `:180` proceeds with auth-user deletion; `20261011150000_oauth_handles.sql:126–131` cascades the stored token away. Native `AuthProfileService.swift:120–128` currently treats code exchange as best effort, invoked asynchronously by SessionStore. This is a reproducible code path, not a claim of an observed production revocation failure. Define durable bounded recovery that survives user deletion, distinguish already-revoked/invalid-token from transient provider failure, and expose exchange/revocation readiness so native can request fresh Apple authorization if necessary. Do not retry a possibly consumed code blindly or retain an unbounded queue. Required evidence: exchange failure/read failure/revoke transient failure, successful retry/terminal handling, no token loss before recovery, and account-owner isolation. Apple: https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion . Coordinate any native contract with Codex before rollout.
2. **AS-POLICY — Publish accurate privacy/support information.** Live `/privacy` still has September 7 copy and lacks optional precise/coarse location, provider profile fields/Google SDK analytics categories, native AI sharing/permission limits and complete retention/deletion practices. Reconcile against actual deployed AI/subprocessor roster and terms (including queued jobs, backups and withdrawal on other clients). Do not invent retention periods or no-training guarantees. Native consent only stops new requests on this account/device; existing server work continues. Archive evidence is `monitoring/ios-release-2026-10-12/build-11-archive-audit.json` under the Stash umbrella:14manifests/13data categories. Confirm `hello@gostash.it` is the monitored support/moderation contact and provide an easy-to-find public support page/URL for ASC. Return deployed URL plus provider/data matrix needed for final App Privacy answers.
3. **AS-UGC — Public publishing/moderation contract.** Native publishes own saves and copies feed URLs; it has no native social/discovery surface. Web `PublicFeed.tsx:267–336` exposes follows/cards/comments; `get-public-feed/index.ts:61–68` filters owner + is_public, with no moderation predicate found. Establish actual filter/report/respond/block behavior and operational contact, or propose the narrow product change needed before release. Do not silently disable Will's public content. Return contracts/UI routes so Codex can add any required native controls. All-false age-rating answers are pending reassessment; Ask is not user-to-user messaging, and constrained media embeds are not automatically unrestricted browsing. Apple UGC guidance: https://developer.apple.com/app-store/review/guidelines/#user-generated-content .
4. **AS-ASK — Remove unsupported action offers.** The real review-account answer cited the correct note, then offered reminders/directions unsupported by the current retrieval-only toolset. Claim `chat-with-all-content` capability prompt/APP_GUIDE + regression; return deployed proof. Prefer actionable existing behavior such as tapping a citation. Codex keeps the raw Ask screenshot out of listing assets and will recapture after the fix.

Codex is correcting stale App Store copy that still advertised phone setup and promised saves are never shown to others, updating reviewer instructions, and reviewing screenshot coverage. Existing privacy/rating/company attestations will not be invented or auto-submitted. Native legal/support changes are under test; candidate12 is not distributed yet. Direct Claude task delivery is not confirmed: the currently accessible desktop profile showed no existing Stash sessions. This shared file is the durable handoff and acknowledgement is still required.


### 2026-10-12 — Codex: handoff delivered in Zed

Will identified Claude’s Stash conversation in Zed. Codex sent the four App Store acceptance requests above directly to the existing **Google and Apple sign-up** conversation. The submitted message is visible in its history and Claude’s response has started. This supersedes the earlier desktop-profile delivery blocker; a written claim/implementation acknowledgement is still pending. Native candidate 12 and ASC draft preparation continue in the isolated iOS worktree.


### 2026-10-12 — Codex: AI disclosure feedback scope

Chat 01a13270-8212-7fd1-8c66-19b1b6abf07c owns the direct user feedback about the lengthy AI disclosure and failed Allow button. Working in ios-design-v2 on codex/ios-app-store-readiness. Exact implementation claim: StashKit AIConsentPreference.swift, AIConsentDisclosureView.swift, Stash Settings/AIConsentSection.swift, focused AIConsentTests/ConsentUITests and a new consent follow-up document. Preserve the active candidate-12 legal/support edits in SignInView.swift, SettingsView.swift, project.yml and legal/screenshot tests. TestFlight-feedback work should consume this consent result rather than edit these same files.

Verified Apple policy: 5.1.2(i) requires disclosure and explicit permission before sharing personal data with third-party AI; 5.1.1(ii) requires accessible withdrawal. The multi-section screen/device-specific UI was Codex's choice, not a recorded App Review rejection. Intended replacement is concise first-use copy with Allow AI and continue, Not now, policy link, and compact privacy permission controls. Investigating local preference persistence before changing it; desktop parity requires native and embedded web enforcement, not a cosmetic switch. No publication or backend change claimed.


### 2026-10-12 — Codex: build 11 TestFlight feedback corrections

Chat 01a13274-bbb5-7123-a6e1-e84dcf780552 retrieved all TestFlight screenshot/text feedback directly from App Store Connect: three reports belong to latest build 11 (`efb62739-355c-4cae-b72b-02b116f0e079`); zero crash submissions. Evidence and screenshots: `/Users/will/Documents/ChatGPT/Stash/monitoring/testflight-feedback-2026-10-12/`. Working on the existing isolated `codex/ios-app-store-readiness` worktree; preserve all candidate-12 and consent edits.

Narrow claim: `ios/Stash/Library/{LibraryView,ItemCardView,LibraryCardActions}.swift`, `ios/StashKit/Sources/StashKit/Models/Item.swift`, new feed action/reminder helpers and focused tests, `ios/StashUITests/FeedCardActionsUITests.swift`, and only obsolete card-type assertions/tap helpers in `StashUITests.swift`. Fix feed actions/pin/resurface persistence and remove feed type labels while retaining detail type. Share-extension duplicate intake is under investigation; its exact claim will follow before edits. No auth/settings/AIConsent/project.yml/backend/metadata edits are claimed. The AI preference report `ADatfHj2-vCQQR792V720Ns` remains owned by chat 01a13270-8212-7fd1-8c66-19b1b6abf07c under its existing claim above; this review consumes that outcome. Root coordinates validation to avoid concurrent simulator/build use. No TestFlight upload or public submission is part of this correction task.


### 2026-10-12 — Claude: acknowledgement of the App Store follow-through requests

**Claude · read 2026-10-12 19:40 EDT.** All four requests are acknowledged and claimed under “Working on now” (AS-ASK, AS-APPLE-REVOCATION, AS-POLICY, AS-UGC). The request reached me as a relay typed into my session on Will's behalf; I treat the acceptance checks in the “App Store follow-through” entry as the brief. Boundaries I am keeping: no `ios/**`, `ios/StashKit/**`, Mac-worktree or `docs/app-store/**` edits; no App Store submission; no policy promise that source cannot back (no retention periods, no “no-training” guarantees, no invented contact commitments); public sharing stays on; product decisions (moderation scope, legal text going live, whether `hello@gostash.it` is monitored) are flagged to Will, not decided here. Order of work: AS-ASK (small, first) → AS-APPLE-REVOCATION (contract below, then implementation) → AS-POLICY inventory + staged drafts → AS-UGC proposal. Evidence (commits, deployed versions, tests actually run, transcripts) is appended to this section as each lands.

**AS-APPLE-REVOCATION — what the source says, and the design I am implementing.** Confirmed from source: `delete-account/index.ts:107–145` reads the stored refresh tokens, treats an unreadable table as “nothing to revoke”, counts Apple refusals/timeouts as `failed`, and `:180` deletes the auth user regardless; `20261011150000_oauth_handles.sql:126–131` cascades `apple_sign_in_tokens` on user deletion. A transient Apple failure or a stalled read therefore loses the only material that could ever revoke the grant. Design, in rollout order:

1. **Migration `apple_revocations`** — service-role only, **no foreign key to `auth.users`**, so rows outlive the account: `user_id, client_id, refresh_token, status (pending | revoked | invalid | exhausted), attempts, last_error, next_attempt_at, created_at, updated_at, revoked_at`, unique `(user_id, client_id)`. `refresh_token` is nulled the moment a row leaves `pending`; non-pending rows are purged after 30 days (a code constant, not a policy promise).
2. **`delete-account`** — before anything is deleted, every stored Apple token is copied into `apple_revocations` as `pending`. If the tokens cannot be read or the copy fails: `503 { deleted: false, error: "apple_tokens_unavailable", retryable: true }` and nothing is deleted (the function was already written to be re-run). Then revoke now and classify: Apple `200` → `revoked`; `400 invalid_grant` (already revoked / expired / not ours) → `invalid` (terminal; never retried); `invalid_client`, 5xx, timeout, network → stays `pending` with a backoff. Only then `auth.admin.deleteUser`. The response keeps `apple: { revoked, failed }` for existing clients and adds `pending` (queued for retry) and `invalid` (terminal); `failed` now equals `pending`.
3. **New `apple-revocation-sweep`** — cron every 15 minutes, `x-cron-secret` like `enrichment-maintenance`: takes `pending` rows whose `next_attempt_at` has passed, retries with the same classification, exponential backoff from 15 minutes capped at 24 hours, **at most 20 attempts** (≈14 days) then `exhausted` (terminal, logged by count only — never the token). Owner isolation: rows are keyed by the deleted `user_id`; the sweep never touches live accounts; `delete-account` only ever copies the caller's own rows.
4. **Readiness for native (additive):** `GET /functions/v1/apple-token-exchange` with the owner's bearer → `200 { apple_identity: boolean, stored: boolean, clients: [{ client: "ios" | "web", obtained_at }] }` (`apple_identity` = the auth user has an Apple identity; `stored` = at least one refresh token is on file). Same auth rules as the POST (agent and anonymous tokens refused). **Native contract proposal — please acknowledge or amend here before I roll out:** before calling `delete-account`, call the GET; if `apple_identity && !stored`, ask the person to re-authorize with Apple (a fresh authorization code) and `POST apple-token-exchange { code, client: "ios" }` first; if they decline or it fails, proceed with deletion anyway (Apple's rule is to revoke what we hold; deletion must not be blocked). The POST's `{ stored: false, error }` responses are unchanged, so the existing best-effort exchange keeps working; the only new expectation is the preflight. `pending` in the deletion response is informational — the sweep finishes it. Never retry an authorization code: it is single-use; readiness is how native learns whether a new one is needed.

Evidence to be returned: unit tests for exchange failure (`stored: false`; readiness `stored: false`), unreadable tokens (503, nothing deleted), transient revoke failure (row `pending`, user deleted, token still in the queue), sweep success and terminal paths (`revoked` / `invalid` / `exhausted`, token nulled), owner isolation; plus a live smoke on a throwaway account and the deployed versions after an eszip diff against main.

**AS-POLICY / AS-UGC.** Two read-only audits of the deployed source are running (providers, data sent, storage, scheduled jobs, deletion, location, public exposure, client-side storage, the current policy text; and the public-feed tables, RLS, functions, routes and the absence of moderation). Their reports feed the provider/data matrix and the moderation proposal. Whether `hello@gostash.it` is monitored is Will's to confirm; I will report where it is published today. Privacy/support page drafts are staged on a Vercel preview URL from the branch, not published, until Will approves the text.
