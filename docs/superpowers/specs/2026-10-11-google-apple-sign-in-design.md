# Google and Apple sign-in — design

**Date:** 2026-10-11 · **Status:** design approved in conversation (Will, 2026-10-11); written spec
awaiting review · **Surfaces:** web (`src/`), Chrome extension (`extension/`), iOS (`ios/`) ·
**Backend:** Supabase Auth config, one migration, three edge-function changes.

Will: "let's get google and apple sign up implemented."

## 0. Decisions of record (2026-10-11)

1. **All three surfaces, one spec, shipped in phases** — backend + web first, then the extension,
   then iOS (plan 18). One contract in `docs/ui-changes.md`.
2. **Handle: generate + one-tap confirm.** The server generates a readable handle for a sign-up
   that carries none; the first surface the person reaches that has the step shows it once,
   prefilled, with **Continue**. Username stays immutable afterwards.
3. **Web uses the id-token flow** for both providers (Google Identity Services button, Apple JS
   popup → `signInWithIdToken`). No redirects, no custom auth domain, **no provider client secrets
   in Supabase**. Google's screen says "Continue to Stash"; Apple needs no 6-monthly secret.
4. **The extension signs in through gostash.it** (a bridge) and receives **its own** session.
   No `identity` permission, no provider secrets, no raw project domain anywhere.
5. **iOS is native:** Sign in with Apple (AuthenticationServices) and the GoogleSignIn SDK, both
   through `signInWithIdToken`; Apple's one-shot authorization code is exchanged so the account
   deletion path can revoke Apple tokens.
6. **Apple's web button is Apple-rendered** (black, square, "Continue with Apple"), paired with
   Google's rendered button, so the pair is consistent and brand-correct. (Considered and not
   taken: our own ink button calling `AppleID.auth.signIn()` — allowed by Apple, but it would sit
   next to a Google-rendered button we can't restyle.)

Defaults taken without a question (sensible, reversible): the try-stash wall keeps its
email/password conversion in v1; Settings gets no "connected sign-ins" UI yet; the Supabase
custom-domain add-on is not bought.

## 1. Why

`docs/ETHOS.md`: lowest-friction in. Today the way in asks a new person to invent a password and a
handle before they have saved anything. One tap with the account they already have removes both,
and on iOS it is the expected way in. Nothing about capture or enrichment changes — this is purely
the door.

## 2. Goals and non-goals

**Goals**

- A new person creates a Stash account with Google or Apple on the web, in the extension (via the
  web), and in the iOS app, and gets the same profile, feed address, and trial as an email sign-up.
- A returning person signs back in with the same provider on any surface.
- An existing email account signing in with Google/Apple **at the same verified email** lands in
  that account — no duplicate.
- Password sign-in, reset, the anonymous try-stash session, MCP consent (`/oauth/consent`),
  admin, and account deletion keep working unchanged for everyone.
- Every account ends up with a handle the person saw and accepted (or chose).

**Non-goals (v1)** — recorded as follow-ups in §13: OAuth on the try-stash wall; linking a second
provider to an existing account from Settings; unlinking; a custom auth domain; the macOS
wrapper; Apple server-to-server notifications.

## 3. Current state (facts gathered 2026-10-10/11)

- Web: email + password only (`src/hooks/useAuth.tsx` `signUp`/`signInWithPassword`); the v2 way
  in (`src/pages/Auth.tsx`, `src/components/auth/AuthShell.tsx`, DESIGN-v2 §12.14) with Sign in /
  Sign up tabs, `returnTo` / `commentItem` / `mode=signup|reset` deep links, the anonymous-session
  guard, live username and phone availability checks. supabase-js 2.50.2 (auth-js 2.70.0),
  `flowType: 'implicit'`, `detectSessionInUrl` on.
- Prod auth config (Management API `GET /config/auth`): `external_google_enabled = false`,
  `external_apple_enabled = false`, `mailer_autoconfirm = true`, anonymous sign-ins on,
  `security_manual_linking_enabled = false`, `uri_allow_list` = gostash.it + localhost:8080. No
  custom domain (requires the Pro-plan add-on).
- `handle_new_user` (migration `20260821200000`) inserts `user_profiles(id, username,
  display_name)` from `raw_user_meta_data.username` / `display_name`, falling back to
  `guest-<8 chars of id>` and the email local part. `user_profiles.username` is `UNIQUE NOT NULL`;
  Settings says "Your username can't be changed." (`AccountSettings.tsx:146`). Columns: `id,
  username, display_name, bio, avatar_url, public_feed_enabled, first_name, last_name, created_at,
  updated_at`. Owner `UPDATE` policy exists (`auth.uid() = id`), `SELECT` is public.
- iOS: `SignInView` (Sign in / Sign up, email/password/username/phone) over
  `SessionStore.signIn/signUp` → supabase-swift 2.x (`signInWithIdToken` available). No URL
  scheme, no `applesignin` entitlement (`ios/Stash/Stash.entitlements`). Bundle
  `it.gostash.stash`, team `3CH3K9NTT2`, xcodegen `ios/project.yml`.
- Extension 1.2.1: its own email/password form (`signin.html`/`signin.js`) over the raw GoTrue
  password grant (`stash-api.js`), session in `chrome.storage.local`; "No account yet? Create one
  at gostash.it". Permissions `contextMenus, storage, scripting`. Distributed as an unlisted hosted
  zip (`extension/scripts/publish-hosted-zip.sh`); Web Store submission pending.
- Trial creation is not on the sign-up path: `SubscriptionProvider.checkSubscription` self-heals
  a trial for any account without one (`useAuth.tsx` comment, `check-subscription`).
- App Store Review 4.8 (verified 2026-10-11): an app using a third-party login to set up the
  primary account must also offer a login service that limits data to name + email, lets the
  person hide their email, and doesn't collect interactions for advertising — Sign in with Apple
  qualifies. Apple's account-deletion guidance: apps using Sign in with Apple "should use the
  Sign in with Apple REST API to revoke user tokens" when an account is deleted.
- Supabase docs (fetched 2026-10-11): id-token sign-in needs only the provider Client IDs; the
  Apple client secret (regenerated every 6 months) is for the redirect flow only; Apple's token
  never carries the name — it arrives once, on first authorization, and must be written by the
  client; identities with the same verified email are linked automatically; `linkIdentity`
  (anonymous → OAuth) requires manual linking to be enabled.

## 4. Contract (all platforms)

### 4.1 Providers and the token path

- Providers: **Google** and **Apple**. Every client obtains an identity token from the provider
  itself and calls Supabase `signInWithIdToken({ provider, token, nonce })`. Supabase validates
  the token against the provider's keys and the configured Client IDs.
- **Nonce rule:** per attempt the client makes a random nonce, gives the provider its SHA-256
  (hex) and Supabase the raw value. Nonces are single-use. (Fallback for an SDK that cannot carry
  a nonce — only the GoogleSignIn iOS SDK below a nonce-capable version: `skip_nonce_check` on
  for Google, documented in the plan.)
- No client ever handles a provider client secret. Supabase holds **none** (both providers are
  enabled with Client IDs only). The one Apple key (`.p8`) lives in edge-function secrets and is
  used solely to mint the short-lived client-secret JWT for the token exchange and revocation
  calls (§5.3).

### 4.2 Accounts and linking

- One account per verified email. Supabase's automatic linking attaches a Google/Apple identity
  to the existing user with the same (confirmed) email; all accounts here are confirmed
  (`mailer_autoconfirm`). The person lands in their existing stash.
- An OAuth-created account has no password. Password reset still works for it (it sets one) and
  so does `updateUser({ password })`, but v1 offers neither as a feature; the sign-in failure copy
  points to the buttons (§4.6).
- **Apple "Hide My Email"** yields a `@privaterelay.appleid.com` address. If that person already
  has an email account, Apple + hide creates a second account; automatic linking cannot see
  through the relay, and manual linking is off. Copy says "one account per email, sign in the same
  way each time". Follow-up §13.
- Signing in with a provider while an anonymous try-stash session is active replaces that session
  exactly as password sign-in does today (the anonymous items are not carried over — an existing
  loose end, unchanged).

### 4.3 The handle

- New column `user_profiles.handle_confirmed boolean not null default true` (existing rows chose
  theirs).
- **`handle_new_user` v3.** When `raw_user_meta_data.username` is present (the email sign-up forms
  on web and iOS send it): use it, `handle_confirmed = true`. Otherwise generate, and set
  `handle_confirmed = false`:
  - anonymous user (`auth.users.is_anonymous`): `guest-<first 8 of id>` (unchanged);
  - everyone else: the first non-empty of `full_name` / `name` from the metadata, then the email
    local part **unless** the domain is `privaterelay.appleid.com`, then `stash`; sanitized to
    `[a-z0-9]`, padded to at least 3 characters (digits from the id), cut to 20; then deduped with
    a numeric suffix (`will`, `will2`, `will3`, …; after 50 tries, 4 hex characters of the id);
  - collision-safe: the insert retries on `unique_violation` with the next candidate, so two
    sign-ups racing for the same base both succeed.
- **The confirm step** (web §6.3, iOS §8): shown when the signed-in person's profile has
  `handle_confirmed = false`. Prefilled with the first available of a name-derived suggestion
  (when the client learned a name — Google always, Apple on first authorization) and the server's
  handle. **Continue** writes `username` (if changed) and `handle_confirmed = true` through the
  owner `UPDATE` policy. Validation and copy are the sign-up form's. There is no skip: the
  prefilled handle plus Continue *is* the skip.
- **Immutability becomes server-side:** a `BEFORE UPDATE` trigger on `user_profiles` refuses a
  `username` change once `handle_confirmed` is true, and refuses setting `handle_confirmed` back
  to false. The confirm step is the only way a handle ever changes.
- A generated handle works everywhere in the meantime (feed URL, `@handle` on shares); the step
  simply appears on the next surface that has it. Side effect worth having: today's try-stash
  conversions keep `guest-xxxxxxxx` forever — they now get the step on their next `/home`.

### 4.4 Display name and avatar

- Trigger v3 sets `display_name = coalesce(meta.display_name, meta.full_name, meta.name,
  <email local part unless relay>, <handle>)` and `avatar_url = coalesce(meta.avatar_url,
  meta.picture)`. Google supplies `full_name`, `name`, `picture`/`avatar_url`.
- Apple supplies the name **only on first authorization and only to the client**. The client
  writes it right after sign-in: `updateUser({ data: { full_name, given_name, family_name } })`
  and `user_profiles.display_name` (plus `first_name`/`last_name`) **when the profile's
  display name is still the server fallback** (equals the username or the email local part) — a
  chosen display name is never overwritten.

### 4.5 What does not change

Trial self-healing; `check-subscription`; admin stats; the agent-token fence; `/oauth/consent`
(its bounce via `/auth?returnTo=…` works because the id-token flow never leaves the page);
`delete-account`'s client contract (`200` → drop the local session); the share pages; iOS share
extension and its keychain session.

### 4.6 Shared copy (machine voice, DESIGN-v2 §12.14)

| Where | Copy |
|---|---|
| Rule between the provider pair and the form | `or with your email` |
| Footnote under the pair (both tabs) | `one account per email. sign in the same way each time.` |
| Handle step | address `stash://handle` · title **Claim your address.** · prompt `> one more thing. pick your handle.` · field helper `gostash.it/feed/<handle>` · button **Continue** · busy `claiming…` · errors `✕ that username is taken. try another.`, `✕ 3–20 letters and numbers.` |
| Sign-in failure, extra line | `Signed up with Google or Apple? Use that button.` |
| Provider sign-in failure (toast) | **Sign-in didn't complete.** + the provider's or Supabase's message |
| Extension sign-in page | **Sign in at gostash.it** · "Sign in once in your browser — with Google, Apple or your email. The extension connects itself." |
| `/extension/connect`, connected | address `stash://extension` · **The extension is connected.** · `> signed in as <email> — you can close this tab.` |
| `/extension/connect`, not installed | **Install the extension first.** · link to `/extension` |
| `/extension/connect`, failed | **That didn't take.** · button **Try again** |

## 5. Backend

### 5.1 Supabase auth config (Management API `PATCH /v1/projects/uqqsgmwkvslaomzxptnp/config/auth`)

| Field | Value |
|---|---|
| `external_google_enabled` | `true` |
| `external_google_client_id` | the **web** OAuth client id (the id-token audience on web, and on iOS via `serverClientID`) |
| `external_google_additional_client_ids` | the **iOS** OAuth client id |
| `external_google_secret` | **unset** (redirect flow only) |
| `external_google_skip_nonce_check` | `false` (see §4.1 fallback) |
| `external_apple_enabled` | `true` |
| `external_apple_client_id` | the **Services ID** (web audience) |
| `external_apple_additional_client_ids` | `it.gostash.stash` (native audience) |
| `external_apple_secret` | **unset** |
| `uri_allow_list` | unchanged (no redirects are added) |
| `security_manual_linking_enabled` | unchanged (`false`) |

Read the config back after the PATCH and keep the result in the plan's verification notes. Mirror
the two providers in `supabase/config.toml` (`[auth.external.google]`, `[auth.external.apple]`,
`enabled = true`, `client_id`, `skip_nonce_check = false`, empty `secret`) so local parity is
documented even though the local stack is not used here.

### 5.2 Migration `20261011120000_oauth_handles.sql`

1. `alter table public.user_profiles add column handle_confirmed boolean not null default true;`
2. `handle_new_user` v3 as in §4.3–4.4 (the v2 body stays in the file, commented, as the rollback).
3. `user_profiles_lock_handle` `BEFORE UPDATE` trigger (§4.3 immutability).
4. `public.apple_sign_in_tokens (user_id uuid references auth.users(id) on delete cascade,
   client_id text not null, refresh_token text not null, created_at timestamptz not null default
   now(), primary key (user_id, client_id))` — RLS enabled, **no policies** (service role only).
5. Recorded in `supabase_migrations.schema_migrations` after applying (the project's convention).

### 5.3 Edge functions

- **`extension-session` (new).** `POST`, standard auth headers, no body. Verifies the caller with
  `getUser(token)` (never a bare `getUser()` — the 2026-10-07 lesson), refuses agent tokens (403,
  the shared guard) and anonymous users (403 `{ error: 'anonymous' }`), then
  `auth.admin.generateLink({ type: 'magiclink', email })` and returns
  `{ token_hash, expires_in }` (`properties.hashed_token`; lifetime = the project's OTP expiry).
  Nothing is emailed. Single-use.
- **`apple-token-exchange` (new).** `POST { code, client: 'web' | 'ios' }`, standard auth
  headers (owner JWT; agent tokens refused). Maps `client` to the Services ID or the bundle id,
  mints Apple's client-secret JWT (ES256 with the `.p8`: `iss` team id, `sub` client id, `aud`
  `https://appleid.apple.com`, `exp` ≤ 15 minutes — minted per call, never stored), posts to
  `https://appleid.apple.com/auth/token` (`grant_type=authorization_code`), and upserts the
  returned `refresh_token` into `apple_sign_in_tokens`. Returns `{ stored: true }`. Apple's code
  is valid for five minutes and single-use, so clients call this immediately after sign-in; a
  failure is logged and never blocks the sign-in.
- **`delete-account` (changed).** Before `auth.admin.deleteUser`: read the caller's
  `apple_sign_in_tokens` rows and `POST https://appleid.apple.com/auth/revoke`
  (`token_type_hint=refresh_token`) for each, with a fresh client-secret JWT. Best effort: a
  revoke failure is logged with the Apple response code and deletion proceeds (the person's
  right to delete is not gated on Apple). The rows disappear with the user (cascade). Because
  prod functions can carry unmerged work (see the agent-coordination notes), the deployed
  `delete-account` is diffed against main before this change is deployed.

### 5.4 Secrets (`supabase secrets set`)

`APPLE_TEAM_ID` (`3CH3K9NTT2`), `APPLE_KEY_ID`, `APPLE_SIGNIN_PRIVATE_KEY` (the `.p8` contents),
`APPLE_SERVICES_ID`, `APPLE_BUNDLE_ID` (`it.gostash.stash`). No Google secret.

## 6. Web

### 6.1 The way in (`/auth`)

- On both tabs, above the form: the **provider pair**, stacked, full width — both rendered at the
  window body's measured inner width (356 px at the 420 px window with `sm:px-8`; GIS accepts
  200–400 px; re-rendered on resize), both 40 px (GIS `large` is fixed at 40; Apple's is set to
  match):
  1. Google — GIS-rendered (`type: 'standard'`, `theme: 'outline'`, `shape: 'rectangular'`,
     `text: 'continue_with'`, `logo_alignment: 'left'`, `width: <measured>`).
  2. Apple — Apple-rendered (`data-type="continue"`, `data-color="black"`,
     `data-border="false"`, `data-border-radius="0"`, `data-width="<measured>"`,
     `data-height="40"`).
- Under the pair: the footnote, then the rule `or with your email`, then the existing fields. The
  Sign up tab keeps username and phone for the email path only.
- Scripts: `https://accounts.google.com/gsi/client` and Apple's `appleid.auth.js` are injected
  **only on `/auth`**, once, by a small `useProviderScripts` hook. If a script fails to load (ad
  or privacy blockers) its slot collapses quietly — the email form is never affected. Client ids
  are public constants (`src/integrations/auth/providers.ts`: web Google client id, Apple Services
  ID, Apple `redirectURI` = `${origin}/auth`).
- Nonce helper `src/utils/nonce.ts`: `{ raw, hashed }` with WebCrypto SHA-256 → hex.

### 6.2 Sign-in per provider

- **Google:** `google.accounts.id.initialize({ client_id, nonce: hashed, callback,
  use_fedcm_for_prompt: true, auto_select: false })` + `renderButton`. The callback's
  `credential` → `supabase.auth.signInWithIdToken({ provider: 'google', token, nonce: raw })`.
  No One Tap prompt in v1 (it would pop over the way in; revisit with data).
- **Apple:** `AppleID.auth.init({ clientId: SERVICES_ID, scope: 'name email', redirectURI,
  usePopup: true, nonce: hashed })` + `renderButton`; `AppleIDSignInOnSuccess` gives
  `authorization.id_token`, `authorization.code`, and on first authorization `user.name` /
  `user.email`. Then `signInWithIdToken({ provider: 'apple', token: id_token, nonce: raw })`,
  the name write (§4.4), and `apple-token-exchange({ code, client: 'web' })`.
  `AppleIDSignInOnFailure` with `popup_closed_by_user` is silent; anything else toasts.
- After either succeeds, `useAuth` sees the session (`onAuthStateChange`) and the existing
  `Auth.tsx` effect routes onward — **after the handle gate** (§6.3). `returnTo` and
  `commentItem` keep working untouched because the page never navigated away.
- Apple's popup cannot run on `localhost`: Apple is tested on the Vercel **branch preview**
  host registered on the Services ID; Google works on localhost.

### 6.3 The handle step and its gates

- `Auth.tsx` grows a third view, `handle` (copy §4.6): the sign-up username field (`@` + mono,
  live availability, same validation), the feed-address helper, one ink **Continue**. Prefill
  per §4.3. Continue → `user_profiles.update({ username, handle_confirmed: true })`; a
  `23505` → field error; any other error → toast, the step stays.
- **Gate in `Auth.tsx`:** the "already signed in → navigate" effect first reads
  `user_profiles.handle_confirmed` for the user (once per session, cached in `useAuth`'s
  context as `handleConfirmed: boolean | null`); while unknown the bar says `| opening…`; `false`
  → show the step; `true` → navigate as today.
- **Gate in `Index.tsx`:** a real user with `handleConfirmed === false` is sent to
  `/auth?mode=handle` (covers extension-first sign-ups and converted try-stash guests);
  `mode=handle` opens the step directly when the flag is false and simply routes onward when it
  is true.
- `/reset-password` is untouched.

### 6.4 `/extension/connect` (phase 2)

- App-shell route. Signed out → `/auth?returnTo=/extension/connect`. Signed in:
  `window.chrome?.runtime?.sendMessage` absent → "Install the extension first." Present → call
  `extension-session`, then `chrome.runtime.sendMessage(EXTENSION_ID, { type: 'stash.session',
  token_hash })`; the extension replies `{ ok: true, email }` → connected state; `lastError` or
  `{ ok: false, error }` → failed state with **Try again** (mints a fresh token). The id lives in
  `src/utils/extensionBridge.ts`. Signed-in anonymous users are bounced to `/auth` like
  everywhere else.
- `signin.html`'s **Sign in at gostash.it** opens this page in a new tab.

### 6.5 Docs and tokens

DESIGN-v2 §12.14 gains the provider pair, the rule, the footnote, `stash://handle` and the
step, and the §10 (Voice and copy) table row; `docs/ui-changes.md` gets the contracts-first entry; the
`PLATFORM_API.md` Auth section names the id-token path, `extension-session`,
`apple-token-exchange`, and the revoke step in `delete-account`.

### 6.6 Tests (vitest)

`Auth`: the pair renders on both tabs; scripts injected once; the Google callback and the Apple
success event call `signInWithIdToken` with the raw nonce whose hash was handed to the
provider; Apple's `user.name` triggers the name write and the code exchange; popup-closed is
silent, other failures toast; the handle view prefills, validates, writes, routes, and maps
`23505` to the field error; the gate waits, shows, or routes. `Index`: the unconfirmed-handle
redirect. `/extension/connect`: not-installed, failed (`lastError`), connected. `nonce.ts`,
`extensionBridge.ts`.

## 7. Extension (phase 2)

- `manifest.json` 1.3.0: a pinned `"key"` (stable id across unpacked, hosted-zip and Web Store
  builds — generate the key pair once, keep the private key outside the repo), and
  `"externally_connectable": { "matches": ["https://www.gostash.it/*", "https://gostash.it/*",
  "http://localhost:8080/*"] }` (the dev origin; Chrome match patterns accept a port here —
  confirmed at build time, falling back to the port-less form if not). No new permissions.
- `signin.html` / `signin.js`: the primary action is **Sign in at gostash.it**
  (`chrome.tabs.create` → `/extension/connect`); the email/password form stays below as the
  secondary path this release; the signed-in state is unchanged.
- `background.js`: `chrome.runtime.onMessageExternal` — accept only `sender.origin` in the
  allow-list, `type === 'stash.session'` → `POST ${SUPABASE_URL}/auth/v1/verify`
  `{ type: 'magiclink', token_hash }` (apikey header) → `toStoredSession(session)` →
  reply `{ ok: true, email }`; a non-2xx (`otp_expired`, reused) → `{ ok: false, error }`. The
  verified session is the extension's own; it never shares a refresh token with a web tab.
- `extension/README.md` updated; hosted zip re-published with the existing script (page and zip
  stay in sync). Tests (`cd extension && npm test`): the external-message handler (origin
  check, verify call, stored shape, error reply) and `signin.js`'s states.

## 8. iOS (plan 18 scope)

- **Buttons:** `SignInWithAppleButton(.continue)` and a Google button drawn to Google's branding
  rules, on both tabs above the fields, mirroring the web order and the `or with your email`
  rule.
- **Apple:** `ASAuthorizationAppleIDRequest` with `[.fullName, .email]` and `nonce = sha256Hex(raw)`;
  `identityToken` → `signInWithIdToken(credentials: .init(provider: .apple, idToken:, nonce: raw))`;
  `fullName` (first authorization only) → the name write (§4.4); `authorizationCode` →
  `apple-token-exchange({ code, client: 'ios' })` right away, one retry, never blocking.
  Entitlement `com.apple.developer.applesignin = [Default]` on the **app** target only
  (`project.yml` → `Stash.entitlements`); the share extension keeps its session via the shared
  keychain as today.
- **Google:** GoogleSignIn-iOS (SPM) with `GIDClientID` (iOS client id) and `GIDServerClientID`
  (web client id, so the token's audience is the web client) in the generated Info.plist, the
  reversed client id as a `CFBundleURLTypes` scheme; `signIn(withPresenting:…nonce:)` where the
  SDK supports it → `signInWithIdToken(.init(provider: .google, idToken:, accessToken:, nonce:))`.
- **Handle step:** `SessionStore.profileLoad` carries `handleConfirmed`; the root switch shows
  `HandleClaimView` (web parity: prefill, validation, Continue) before the tabs when it is false.
- **Copy and identifiers:** §4.6 strings; `auth.apple`, `auth.google`, `auth.handle.field`,
  `auth.handle.continue`. Existing `signin.*` identifiers untouched (plan-7 coexistence rule).
- Account deletion already calls `delete-account`; nothing changes client-side. Build/run/test
  through FlowDeck; Sign in with Apple works on the simulator with an Apple ID signed in.

## 9. Error handling

| Situation | Behaviour |
|---|---|
| Provider popup closed / cancelled | Nothing happens; the way in stays as it was. |
| `signInWithIdToken` rejects (bad nonce, provider disabled, audience mismatch) | Toast **Sign-in didn't complete.** with the message; logged; the person can retry or use email. |
| Provider script blocked | That button's slot collapses; the other button and the email form remain. |
| Same email, existing account | Lands in the existing account (automatic linking). |
| Apple hide-my-email + existing email account | A second account; the footnote explains; follow-up §13. |
| Handle taken at Continue (`23505`) | Field error; the step stays. Network error → toast; the gate re-shows the step next visit (idempotent). |
| Name write or `apple-token-exchange` fails | Logged; sign-in completes; display name stays the server fallback; revocation for that device is impossible later (recorded in the function log). |
| `extension-session` 401/403 | The connect page sends the person to `/auth` (401) or says anonymous accounts can't connect (403). |
| `verify` fails in the extension (expired/used `token_hash`) | `{ ok: false }` → **That didn't take.** / **Try again** mints a new one. |
| Extension not installed / not Chrome | **Install the extension first.** |
| Apple revoke fails during deletion | Logged with Apple's status; deletion proceeds. |
| Anonymous session active when a provider button is used | Replaced by the new session (as password sign-in does today). |

## 10. Security and privacy

- Nonces bind each identity token to the attempt that requested it; tokens go only to Supabase.
- No provider access or refresh tokens are kept by any client; Supabase holds no provider
  secrets. The only stored provider credential is Apple's refresh token, in a service-role-only
  table, used solely to honour deletion, and deleted with the user.
- `extension-session` hands out a single-use, short-lived `token_hash` only to the authenticated
  owner, over the page's own origin, to the pinned extension id; `externally_connectable` plus
  the background's origin check mean no other page or extension can present or receive it. It
  refuses agent tokens and anonymous users.
- Emails to relay addresses: for reminder digests and resets to reach
  `@privaterelay.appleid.com`, `gostash.it` is registered under Apple's *Sign in with Apple for
  Email Communication* (prerequisite §12).

## 11. Testing and verification

- **Unit:** §6.6 (web), §7 (extension), node tests for `extension-session` (401/403/anonymous/
  success with a mocked admin client), `apple-token-exchange` (the client-secret JWT's header and
  claims, signature verified with the key's public half; exchange error mapping; upsert shape),
  `delete-account` (revoke before delete; failure non-blocking).
- **Database:** trigger v3 and the lock trigger are exercised against prod with throwaway
  admin-created users (the existing recipe): metadata username → confirmed; Google-shaped
  metadata → `willdzierson`, unconfirmed; relay email without a name → `stash…`; a forced
  collision → suffix; anonymous → `guest-…`; a confirmed username refuses to change. Cleaned up
  with `delete-account`.
- **Providers, by hand:** Google on localhost and prod with a throwaway Google account; Apple on
  the branch preview and prod with Will's Apple ID, including Hide My Email; an existing email
  account + Google at the same email lands in the same account (`auth.identities` shows two
  rows for one user); iOS on simulator and device; the extension bridge end to end with the
  hosted zip. Evidence kept: `auth.identities`, `user_profiles`, function logs, the read-back
  auth config.
- **Regression:** `npm test`, `cd extension && npm test`, `cd ios/StashKit && swift test`,
  and the existing password/reset/consent walks.

## 12. Rollout and prerequisites

**Phase 0 — Will's consoles (public identifiers only; no secret is pasted into chat).**

- *Google Cloud:* OAuth consent screen (app name Stash, logo, support email,
  `https://www.gostash.it/privacy`, `/terms`; scopes `openid email profile` only — no
  verification needed). A **Web application** client with authorized JavaScript origins
  `https://www.gostash.it`, `https://gostash.it`, `http://localhost:8080`, `http://localhost`,
  and the branch-preview origin; an **iOS** client for `it.gostash.stash`. Deliver: both client ids.
- *Apple Developer (3CH3K9NTT2):* enable Sign in with Apple on App ID `it.gostash.stash`; create a
  **Services ID** (e.g. `it.gostash.web`) with Sign in with Apple configured — primary App ID
  `it.gostash.stash`, domains `www.gostash.it` + the branch-preview host, return URLs
  `https://www.gostash.it/auth` + the preview's `/auth`; create a **Key** with Sign in with Apple,
  download the `.p8` once (goes to `supabase secrets`, §5.4); register `gostash.it` under *Sign in
  with Apple for Email Communication*. Deliver: the Services ID, the Key ID, the `.p8` (to the
  secret store, not chat).
- *Chrome Web Store:* none required — the key pair in §7 is generated locally; the eventual store
  upload inherits the id from the manifest's `key`.

**Phase 1 — backend + web + docs.** Migration applied and recorded; config PATCH + read-back;
web change on this branch (`/auth` pair, nonce, handle step, gates, copy); DESIGN-v2 §12.14,
`ui-changes.md`, `PLATFORM_API.md`, `config.toml`. Merge → push → Vercel. Verified on prod with
the §11 provider walks.

**Phase 2 — extension bridge.** Deploy `extension-session`; web `/extension/connect`; extension
1.3.0 (key, `externally_connectable`, sign-in page, background handler); hosted zip re-published;
walk: fresh profile → install → Sign in at gostash.it → Google → connected → a save lands.

**Phase 3 — iOS plan 18.** Written with the writing-plans skill after phase 1 ships: buttons,
native flows, entitlement and URL scheme, handle step, name write, `apple-token-exchange` and
the `delete-account` revoke (deployed with their secrets), TestFlight build and the App Store
screenshots that show the new way in.

## 13. Known limitations and follow-ups

- **Try-stash wall:** still email/password. OAuth conversion needs manual linking enabled and a
  conflict path for "this provider email already has an account" (move the anonymous items).
- **Connected sign-ins in Settings:** adding Google/Apple to a password account (or the reverse,
  "set a password") and unlinking — needs manual linking; also the remedy for Hide-My-Email
  duplicates.
- **Custom auth domain** (`auth.gostash.it`, Pro add-on): not needed by this design; revisit if a
  redirect-based client ever appears.
- **macOS wrapper (`stash-mac`, Electron 21):** still points at the Lovable URL and Google blocks
  sign-in inside Electron windows; when revived it should reuse the extension's bridge pattern
  (sign in in the browser, hand over a one-time token).
- **Apple server-to-server notifications** (email-forwarding changes, consent revoked): not
  wired; required only for Korea-based developers.
- **One Tap** on the way in: deliberately off in v1.

## 14. Files touched (expected)

- `supabase/migrations/20261011120000_oauth_handles.sql`; `supabase/config.toml`
- `supabase/functions/extension-session/`, `supabase/functions/apple-token-exchange/`,
  `supabase/functions/delete-account/index.ts`, `supabase/functions/_shared/appleClientSecret.ts`
- `src/pages/Auth.tsx`, `src/components/auth/ProviderButtons.tsx`,
  `src/components/auth/useProviderScripts.ts`, `src/components/auth/HandleStep.tsx`,
  `src/hooks/useAuth.tsx`, `src/pages/Index.tsx`, `src/pages/ExtensionConnect.tsx`,
  `src/App.tsx`, `src/integrations/auth/providers.ts`, `src/utils/nonce.ts`,
  `src/utils/extensionBridge.ts`, tests beside each
- `extension/manifest.json`, `extension/signin.html`, `extension/signin.js`,
  `extension/background.js`, `extension/stash-api.js`, `extension/README.md`, tests
- `ios/` (plan 18): `project.yml`, `Stash.entitlements`, `Auth/SignInView.swift`,
  `Auth/SessionStore.swift`, `Auth/HandleClaimView.swift`, `Auth/ProviderSignIn.swift`
- `docs/ui-changes.md`, `DESIGN-v2.md` §12.14 + §10, `docs/PLATFORM_API.md`
