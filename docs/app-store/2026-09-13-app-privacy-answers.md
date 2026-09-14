# App Privacy (nutrition label) questionnaire answers — 1.0

Date: 2026-09-13. App Store Connect's App Privacy questionnaire cannot be
set via the REST API — Will clicks these answers by hand at **App Store
Connect → Stash → App Privacy**. They must stay consistent with
`ios/Stash/PrivacyInfo.xcprivacy`, `ios/StashShareExtension/PrivacyInfo.xcprivacy`,
and `src/pages/Privacy.tsx` (the live privacy policy).

## Does this app collect data?

**Yes.**

## Data types collected

For every type below: **linked to the user's identity = Yes**, **used for
tracking = No**, **purpose = App Functionality** only (no Analytics,
Advertising, Third-Party Advertising, Product Personalization, or Other
purposes selected for any type).

| Data type | Collected | Linked to identity | Used for tracking | Purpose |
|---|---|---|---|---|
| Email Address | Yes | Yes | No | App Functionality |
| Phone Number | Yes | Yes | No | App Functionality |
| User ID | Yes | Yes | No | App Functionality |
| Photos or Videos | Yes | Yes | No | App Functionality |
| Audio Data | Yes | Yes | No | App Functionality |
| Other User Content | Yes | Yes | No | App Functionality |
| Coarse Location | Yes | Yes | No | App Functionality |

Everything else on Apple's full list (Precise Location, Contacts, Search
History, Browsing History, Health & Fitness, Financial Info, Purchases,
Identifiers/Device ID beyond the account User ID, Usage Data, Diagnostics,
Advertising Data, etc.) — **not collected**.

## Why each type is declared this way

- **Email Address** — the account email (Supabase Auth). Used to sign in,
  and referenced by `src/pages/Privacy.tsx` ("Your account information: the
  email address you sign up with").
- **Phone Number** — the optional WhatsApp/SMS capture number
  (`user_phone_numbers.phone_number`), only if the user connects one. Same
  privacy-policy sentence.
- **User ID** — the Supabase auth user id used to associate saved content
  with the account (App Functionality only — not used for tracking across
  apps/websites).
- **Photos or Videos** — images and videos the user explicitly saves
  (camera capture, photo picker, share-sheet image/movie activation).
- **Audio Data** — voice notes recorded in-app and sent for transcription
  (`transcribe-audio`).
- **Other User Content** — everything else the user saves in their own
  words or via capture: notes, link/document text, transcripts, summaries,
  AI-generated titles/descriptions — matches the `content` / `page_body` /
  `summary` / `description` lanes described in `CLAUDE.md`'s data-model
  section and `src/pages/Privacy.tsx`'s "The content you save" paragraph.
- **Coarse Location** — the optional location pin (`LocationCapture.swift`).
  Declared as **Coarse**, not Precise: `LocationCapture.swift` sets
  `manager.desiredAccuracy = kCLLocationAccuracyHundredMeters` (~100m) and
  never calls
  `requestTemporaryFullAccuracyAuthorization`, so the app never asks for or
  relies on the ~50m-or-finer accuracy Apple's own guidance treats as the
  "Precise Location" threshold. If a future change starts requesting a finer
  accuracy, re-run this check and switch the manifests + this doc to
  Precise Location before shipping.

## Not collected — explicitly ruled out

- **Precise Location** — see above; the app only ever requests
  hundred-meter accuracy.
- **Contacts, Browsing/Search History, Health & Fitness, Financial Info,
  Purchases** — no code paths read or transmit any of these; there is no
  in-app purchase (subscriptions are managed entirely on gostash.it).
- **Usage Data / Diagnostics / Advertising Data / any Identifiers used for
  tracking** — no analytics or advertising SDKs are integrated; `Privacy.tsx`
  states "We do not sell your data. We do not show you ads."
- **Active Keyboards, Disk Space, System Boot Time** — no corresponding
  required-reason APIs are called anywhere in `ios/Stash`,
  `ios/StashShareExtension`, or `ios/StashKit/Sources` (verified by grep;
  see the manifests' inline comments).

## Data used for tracking

**No** — `NSPrivacyTracking` is `false` in both manifests, no linked
identifiers are shared with third parties for cross-app/cross-site
advertising, and `NSPrivacyTrackingDomains` is empty in both.

## Third-party SDKs

None of the infrastructure providers Stash relies on (Supabase, OpenAI,
Stripe, Twilio, Firecrawl — per `src/pages/Privacy.tsx` "Services we rely
on") are consumer-facing SDKs embedded in the iOS binary that collect data
independently; the iOS app talks to them exclusively through Stash's own
backend (Supabase edge functions), not via bundled third-party SDKs. No
additional third-party data-collection entries are needed for this reason.

## Required-reason API grep evidence (backs the manifests, not the ASC UI)

```
$ grep -rn "UserDefaults" ios/Stash ios/StashShareExtension ios/StashKit/Sources
Stash/Onboarding/OnboardingState.swift        UserDefaults.standard (app target)
StashShareExtension/ShareComposeView.swift    UserDefaults(suiteName: AppGroup.identifier) (extension target)
StashKit/Sources/StashKit/SubscriptionStore.swift  UserDefaults(suiteName: AppGroup.identifier) (linked into both targets)
→ NSPrivacyAccessedAPICategoryUserDefaults, reason CA92.1, both manifests.

$ grep -rnE "modificationDate|creationDate|contentModificationDateKey|attributesOfItem|\bstat\(" ios/Stash ios/StashShareExtension ios/StashKit/Sources
StashKit/Sources/StashKit/StagedFileStore.swift:238   .contentModificationDateKey
StashKit/Sources/StashKit/Outbox.swift:303,308        .contentModificationDateKey
→ NSPrivacyAccessedAPICategoryFileTimestamp, reason C617.1, both manifests (StashKit links into
  both the Stash app target and the StashShareExtension target).

$ grep -rnE "volumeAvailableCapacity|systemFreeSize" ios/Stash ios/StashShareExtension ios/StashKit/Sources
(no matches) → disk space API category omitted from both manifests.

$ grep -rnE "systemUptime|mach_absolute_time" ios/Stash ios/StashShareExtension ios/StashKit/Sources
(no matches) → system boot time API category omitted from both manifests.

$ grep -rnE "activeInputModes|UITextInputMode" ios/Stash ios/StashShareExtension ios/StashKit/Sources
(no matches) → active keyboards omitted from both manifests.
```
