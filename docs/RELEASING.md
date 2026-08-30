# Releasing Stash for iOS

How to get a new build of the iOS app onto TestFlight. Written so an agent
can run the whole pipeline unattended; the one human dependency (a signed-in
Xcode session) is called out explicitly below.

## Prerequisites

- **Xcode signed in** with an Apple ID on team `3CH3K9NTT2` (Xcode → Settings
  → Accounts). This is what actually signs the archive/export/upload — see
  "The auth split" below. If this session expires, see Troubleshooting.
- **`xcodegen`** installed (regenerates `Stash.xcodeproj` from `project.yml`).
- **App Store Connect API key** at `ios/.asc/` — only needed for (a) the REST
  calls in this doc (processing polls, TestFlight group/tester management) and
  (b) the `--key-auth` fallback mode of `release.sh`, never for a normal
  release. See `ios/.asc/README.md` to generate one (role **App Manager**)
  and drop it; everything in that folder except the README is gitignored.
- Run all commands from `ios/`.

Key facts, none of them secret: team ID `3CH3K9NTT2`; bundle IDs
`it.gostash.stash` (app) / `it.gostash.stash.share` (share extension); ASC
app ID `6806459949`.

## The auth split (read this before debugging an auth failure)

Two different credentials do two different jobs in this pipeline. They are
**not interchangeable** — this was learned the hard way (plan-6 Task 4):

| Operation | Auth used | Why |
|---|---|---|
| `xcodebuild archive` / `-exportArchive` (export **and** upload) | **Xcode session** (the signed-in Apple ID) | The App Store Connect API key's cloud-signing path fails on this account/team when passed to xcodebuild via `-authenticationKeyPath/-authenticationKeyID/-authenticationKeyIssuerID` — it errors with **"Cloud signing permission error"** (and, with a stale/no profile, "No profiles ... found"). Session auth is the only path that has ever produced a valid archive/export/upload on this setup. |
| ASC REST calls (build-processing polls, beta groups, beta testers, users, apps) | **ASC API key** (`ios/.asc/AuthKey_<KEYID>.p8` + `ios/.asc/config.env`, JWT-signed) | The key works perfectly here — every REST call made during Task 5 (apps lookup, builds poll, betaGroups create, betaTesters create, build-to-group attach) succeeded on the first try, with zero role errors. |

Practical upshot: `ios/scripts/release.sh` defaults `archive`/`export`/`upload`
to session auth and never asks for the key. Pass `--key-auth` (or set
`STASH_RELEASE_AUTH=key`) to force the old API-key path — useful only if
Apple ever fixes cloud signing for this account; `release.sh` fails fast
with an actionable message if you request that mode without a key present,
rather than silently falling back to session auth.

## One-command release

```bash
cd ios
./scripts/release.sh generate   # only needed after a project.yml edit
./scripts/release.sh archive
./scripts/release.sh upload
```

No flags, no key. `upload` re-exports the archive using
`scripts/ExportOptions-upload.plist` (`destination: upload`), which makes
`xcodebuild -exportArchive` package **and** upload the `.ipa` to App Store
Connect in that single step — there's no separate submit action.

If you ever need the explicit local `.ipa` without uploading (e.g. to
inspect entitlements), `./scripts/release.sh export` writes it to
`build/export/Stash.ipa` instead.

## Version / build-number bump rule

Both settings live once, at the top of `ios/project.yml`
(`settings.base`), and every target inherits them — never set a per-target
copy (a stale per-target literal was exactly the bug plan-6 Task 2 fixed for
the share extension).

- **`CURRENT_PROJECT_VERSION`** (build number) — **bump before every single
  upload.** App Store Connect permanently rejects a re-upload of a
  version+build pair it has already seen, even a byte-identical rebuild.
- **`MARKETING_VERSION`** (user-facing version, e.g. `0.1.0`) — bump per
  actual release, not per build.

Run `./scripts/release.sh generate` (or `xcodegen generate`) after bumping
either, before archiving.

## Processing & beta-review expectations

- **Processing** (upload accepted → build usable): Apple typically quotes
  5–15 minutes; observed 2026-08-30 end to end: about **1 minute**. Poll
  `GET /v1/builds?filter[app]=<id>&sort=-uploadedDate` (ASC API key JWT) and
  watch `processingState` go `PROCESSING` → `VALID` (or `INVALID`/`FAILED`,
  which arrives with an explanatory email from Apple — nothing to script
  around there).
- **Export compliance**: both Info.plists ship `ITSAppUsesNonExemptEncryption:
  false`. App Store Connect picks this up automatically — the build
  resource's `usesNonExemptEncryption` attribute resolves to `false` with no
  manual compliance step and no PATCH required (confirmed via the REST API
  immediately after processing finished).
- **Internal testing**: no beta review. The moment a build is `VALID` and
  attached to an internal group, that group's testers can install it.
- **External testing**: requires Apple Beta App Review, ~1 day typical. Not
  exercised by this plan — v1 ships Internal only, per spec.

## TestFlight group/tester management (all via REST, same API key)

The JWT recipe is in
`.superpowers/sdd/2026-08-24-ios-plan-6-testflight/asc-auth-probe.sh`. The
calls that matter:

- `GET /v1/apps/<id>/betaGroups` — check what groups already exist before
  creating one (avoid duplicate "Internal" groups).
- `POST /v1/betaGroups` with `attributes.isInternalGroup: true` and an `app`
  relationship — creates an internal group.
- `POST /v1/betaTesters` with `email`/`firstName`/`lastName` and a
  `betaGroups` relationship — adds a tester to that group. **For internal
  groups this only works for people who are already App Store Connect
  Users on the team** (Users and Access); the API rejects arbitrary
  external emails for an internal group (that's what external groups are
  for). Will (`willdzierson@gmail.com`, ACCOUNT_HOLDER/ADMIN) qualifies, and
  this call succeeded on the first try with no role error.
- `POST /v1/betaGroups/<id>/relationships/builds` — attaches an uploaded,
  `VALID` build to a group so its testers can see it.

No Will-checkpoints remain for future releases: with Xcode signed in, the
entire archive → export → upload → TestFlight-group/tester pipeline is
agent-runnable end to end.

## Troubleshooting

**Archive suddenly fails with "login details for account '...' were
rejected"** — the Xcode session expired. Fix: Xcode → Settings → Accounts →
sign out and back in for the Apple ID on team `3CH3K9NTT2`, then retry. This
is the one manual step that can reintroduce a human checkpoint; everything
else in the pipeline is unattended.

**"No profiles for '...' found" / "Cloud signing permission error"** —
something requested key auth (`--key-auth`, `STASH_RELEASE_AUTH=key`, or a
hand-run `xcodebuild` with `-authenticationKey*` flags). This account's API
key cannot cloud-sign via xcodebuild on this team. Drop the flag/env var —
default session auth is the proven path.

**Don't drop `-allowProvisioningUpdates` from export/upload** — it's
well-known on `archive`, but it's also load-bearing on `-exportArchive` for
both `export` and `upload` on this setup: without it there too, automatic
signing can fail to refresh/select a profile at export time even when the
archive itself is fine (T3 review-ledger note). `release.sh` passes it on
all three subcommands; if you're ever running `xcodebuild -exportArchive` by
hand, keep it.

**`error: no App Store Connect API key found...`** from `release.sh` — only
fires when key auth was explicitly requested (`--key-auth` /
`STASH_RELEASE_AUTH=key`) and `ios/.asc/config.env` or the `.p8` is missing.
Follow `ios/.asc/README.md`. Default session mode never triggers this.

**A freshly-added internal tester still shows `NOT_INVITED` several minutes
after being added** — observed 2026-08-30: tester creation and group/build
attachment all succeeded via the API (HTTP 201/204,
`buildBetaDetail.autoNotifyEnabled: true`,
`buildBetaDetail.internalBuildState: IN_BETA_TESTING`), but Apple's invite
email dispatch is an internal async process with no public "send now" API
call. Give it a while and check spam. If it never arrives, the fallback is
two clicks in the UI: **App Store Connect → your app → TestFlight → Internal
Testing → Internal group → select the tester → Resend Invite** (or remove
and re-add the tester to the group).
