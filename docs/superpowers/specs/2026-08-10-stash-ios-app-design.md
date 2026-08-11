# Stash iOS app — design

**Date:** 2026-08-10 · **Status:** approved by Will 2026-08-10 (tab order/name amended: Add · Ask · View · Settings) · **Scope:** new native iOS client for the existing Stash platform

## Summary

A native SwiftUI iPhone app that is a thin client on the existing platform API
(`docs/PLATFORM_API.md`): all capture and retrieval intelligence stays in Supabase
edge functions; the app owns presentation, native capture surfaces, and an offline
outbox. Bottom tab bar: **Add · Ask · View · Settings**, with Add as the launch tab —
the app opens ready to capture. The reason this app exists
is capture friction: system share sheet from any app (links, text, screenshots,
photos, PDFs), voice notes, home/lock screen widgets, and Siri/Shortcuts intents
that can save without opening the app.

## Goals

- Parity for the personal core: capture, library browse/filter/search, item detail
  with the same type-appropriate tabs as the web edit panel, edit
  (title/description/tags/notes-append/public toggle + sticky note), delete,
  Ask Stash streaming chat with citations.
- Capture from anywhere: share extension, widgets, App Intents, voice notes.
- Reliability: every capture eventually lands (offline outbox, background retry);
  async enrichment arrives live via the existing realtime channel.

## Non-goals (v1)

- Social surfaces in-app: Discover, public feeds, comments, follows (roadmap says
  personal utility first). The per-item public toggle and sticky note ARE included
  since they're part of item editing.
- Full rich-text notes editing. Notes render read-only (TipTap JSON → AttributedString);
  editing is append-only: a composer that appends paragraph nodes to the TipTap doc
  (or plain text onto plain items). Full parity editor is post-v1.
- Account creation (sign-in only; accounts are created on gostash.it — signup's
  username/phone flow stays in one place).
- Payments in-app. Subscription state is displayed and gates capture/AI exactly like
  the web (`canAddContent`), with "manage on gostash.it" when expired. IAP vs
  US external-purchase-link is decided at App Store submission; TestFlight first.
- Collections assembly UI (web only creates them implicitly on mixed submits; iOS v1
  submits multiple attachments as separate items), Spotlight indexing, push
  notifications, iPad/visionOS layout tuning, full offline sync.

## Approach chosen (and alternatives rejected)

**A. Native SwiftUI on the platform API — chosen.** supabase-swift for
auth/PostgREST/storage/realtime; raw URLSession for the SSE chat stream (same
reason the web client uses raw `fetch`). Share extension, widgets, and App Intents
are first-class. Second codebase to maintain, but the server owns the intelligence
so drift surface is small — that was the explicit design goal of PLATFORM_API.md.

**B. Web wrapper (WKWebView/Capacitor, like stash-mac) — rejected.** Share
extension/widgets/intents still require native code plus a JS bridge; the web app is
desktop-shaped today (2 MB bundle, no pagination, the capture panel already
auto-collapses on WebKit because it's cramped there); capture UX would feel webby,
which defeats the purpose.

**C. React Native/Expo — rejected.** Reuses TS, but extensions and widgets are
native modules anyway, and it adds a third runtime to the stack for no capture-UX
gain.

## Architecture

**Workspace targets**

| Target | Purpose |
|---|---|
| `Stash` (app) | Tabs, capture composer, detail sheets, settings |
| `StashShareExtension` | System share sheet capture from any app |
| `StashWidgets` | WidgetKit widgets + App Intents (shared intent definitions) |
| `StashKit` (local Swift package) | Everything shared — see modules below |

**StashKit modules**

- `StashAPI` — typed client for `add-url`, `add-note`, `add-file` (new, below),
  `chat-with-all-content` (SSE via `URLSession.bytes`), `check-subscription`,
  `summarize-content`, `generate-embeddings`, `get-relevant-tags`; plus the
  supabase-swift client (auth, PostgREST reads, storage upload, realtime).
- `MessageRouting` — Swift port of `src/utils/moleRouting.ts` (documented client
  contract): URL → add-url, `remember:`/`save:`/`note:` → add-note, else chat.
- `Models` — `Item` (mirrors `items` columns incl. `content`/`page_body`/`summary`/
  `description` semantics), `ItemType`, `Tag`, `Subscription`. The
  "still processing" rule is a port of `isDocumentProcessing()` (`summary IS NULL`).
- `SessionStore` — supabase-swift auth with a shared keychain access group +
  App Group so extensions/widgets read the session. Refresh policy below.
- `Outbox` — pending captures as JSON files in the App Group container with
  client-generated UUIDs; drained on app foreground, via `BGTaskScheduler`, and
  opportunistically after any successful send.
- `ItemStore` — cursor pagination (`created_at desc`, 50/page — deliberately better
  than the web's fetch-everything), server-side type filter and tag filter
  (PostgREST `item_tags!inner` join), realtime merge (channel `items-{userId}`,
  400 ms debounce like the web), first-page disk cache for cold start/offline read.

**Config:** bundle ids `it.gostash.stash` / `.share` / `.widgets`; App Group
`group.it.gostash.stash`; URL scheme `stash://` (capture modes + item deep links);
min iOS 17 (interactive widgets); built with the Xcode 26 SDK so the tab bar gets
current-OS styling for free. Supabase URL + anon key are public constants, same as
the web client.

## Screens

**View tab** (the library) — search field (local filter over loaded pages, same fields as
`itemSearch.ts`, with an "Ask Stash searches everything" affordance for deep
recall), type chips (all/links/notes/docs/media — shipping the `typeFilter` the web
built but never wired), tag filter sheet, card grid (thumbnails from `file_path`/
preview image via `image-proxy`, favicon fallback, processing shimmer per the
`summary IS NULL` rule), pull-to-refresh, infinite scroll. Card tap → detail sheet.
Context menu: share, public/private, delete (confirm; delete embeddings then row,
mirroring `itemOperations.ts`).

**Item detail sheet** — tabs per `editPanelTabs.ts` mapping (link/document:
Summary · Original · Notes; audio/video: Notes · Transcript; text/image: Notes),
editable title + description (PATCH then fire-and-forget `generate-embeddings`,
mirroring the web's decoupled reindex), Generate-summary button
(`summarize-content`) in empty Summary states, tags manager with AI suggestions
(`get-relevant-tags`), notes append composer, public toggle + sticky note
(public items only; un-share confirms and clears the note, matching web), audio
player for voice notes.

**Add tab** — the resident capture composer and launch tab (keyboard raises on
tap, not on launch): text editor
with dictation, URL auto-detection chip (port of the unified panel behavior),
PhotosPicker + camera + document picker attachments, voice-note recorder
(waveform, live on-device transcript preview), AI tag suggestions, public toggle.
Submit routing ports `UnifiedInputPanel`: URL (+optional text) → `add-url`;
text → `add-note`; each file → storage upload + `add-file`. Optimistic local chip;
realtime settles title/description exactly like the web's fast-chip model.

**Ask tab** — ChatMole parity: streaming SSE answer, markdown rendering, citation
chips that open the item detail sheet, history restored from
`conversations`/`messages` (same single-conversation model), voice input via
native speech recognition (the PLATFORM_API-sanctioned path for platforms that
have it), read-aloud via `AVSpeechSynthesizer`, thumbs feedback → `chat_feedback`.
Composer applies `MessageRouting`, so pasting a URL into Ask saves it with a
confirmation toast — same muscle memory as the web.

**Settings tab** — account info (email, username, public feed URL copy), phone
numbers (parity with web's list/add — inherits the web's auto-verify gap, no new
risk added), tags management, subscription status + trial countdown
(`check-subscription`, 30 s poll only while the tab is visible), sign out, legal
links.

## Share extension (the flagship)

Accepts URLs, selected text, images (screenshots included), PDFs, and multiple
images from any app. Compact compose card: content preview, optional note, Save.
Saves are a direct POST with the shared-keychain JWT — the platform endpoints
return in ~1 s because enrichment is server-async, which makes a self-contained
extension viable with no app wake-up. On any failure (offline, auth, 5xx) the
capture drops into the Outbox and the UI still confirms ("Saved — will sync").
Screenshots therefore work end-to-end today: share → image upload → `add-file` →
`analyze-image` OCRs into `page_body` → searchable via Ask Stash. Images larger
than the web's 20 MB limit are downscaled client-side before upload (also keeps the
extension inside its ~120 MB memory ceiling).

## Widgets, App Intents, voice

- **Home Screen widget** (small/medium): Note · Voice · Save-link buttons.
  **Lock Screen** accessory widget and **iOS 18+ Control Center control /
  Action Button**: one-tap capture. Platform constraint stated plainly: widgets
  cannot host a keyboard or microphone, so these launch the app directly into the
  right capture mode via `stash://` (one tap → ready to type/record).
- **App Intents** are the true no-app-open path: `SaveNoteToStash(text)`,
  `SaveClipboardToStash`, and `AskStash(question)` run in the background —
  "Hey Siri, save a note to Stash" dictates and saves without ever opening the app,
  via StashAPI + Outbox. Composable in Shortcuts (e.g., an automation that saves
  the clipboard every time you screenshot).
- **Voice notes** (distinct from dictation): AVAudioRecorder m4a → storage upload +
  `add-file` → existing `transcribe-audio` (Whisper) puts the transcript in
  `page_body` → realtime updates the card. Server Whisper stays the source of truth
  (parity with the SMS/WhatsApp voice path); the live on-device transcript during
  recording is preview-only. Dictation (voice → text input) uses native speech
  recognition per PLATFORM_API.

## Backend prerequisite: `POST /add-file` (the only server work)

PLATFORM_API.md already names this as the intended next step; without it the iOS
client must replicate ~450 lines of orchestration from `contentProcessor.ts`.

Contract: client uploads to `stash-media/<userId>/<uuid>.<ext>`, then

```json
{ "file_path": "…", "mime_type": "…", "file_size": 123, "content": "optional note", "title": "optional", "is_public": false }
```

Server (JWT-authed like add-url/add-note): inserts the typed item (image/audio/
video/document from MIME), returns `{ success, item }` fast, then via
`EdgeRuntime.waitUntil` runs the type's enrichment (`analyze-image` |
`quick-pdf-summary` + `extract-pdf-text` | `transcribe-audio`) and
`generate-embeddings`. Deployed with the supabase CLI per the usual process.
Migrating the web's upload path onto it is explicitly out of scope here.

## Error handling

- **Offline/failed capture** → Outbox with client UUID; drain on foreground,
  BGTask, and after successful sends. Pending items show a "will sync" chip.
  Known accepted gap: the add-* endpoints don't dedupe, so a retry after an
  ambiguous failure can rarely duplicate an item (no new server work in v1).
- **Auth in extensions:** use the stored access token; supabase-swift refreshes
  single-flight, and Supabase's refresh-reuse grace window covers the rare
  cross-process race. If refresh fails, capture goes to the Outbox and the main
  app shows the sign-in screen. Lesson applied from the zombie-session incident:
  "Auth session missing" is treated as signed-out state, never an error loop.
- **SSE drop mid-answer:** keep partial text, show retry.
- **Realtime disconnect:** refetch on foreground (same recovery the web relies on).
- **Limits:** mirror web (20 MB images/docs, 100 MB A/V); images downscale,
  others reject with a clear message.
- **Subscription gates:** client-side, identical semantics to `useSubscription`
  (fail-open while loading). Extension reads cached gate state from the App Group.

## Testing

- StashKit unit tests: `MessageRouting` table-driven against the documented
  contract; Outbox persistence/drain/idempotency; TipTap paragraph-append JSON
  safety; pagination+realtime merge; SSE parser.
- XCUITest smoke on simulator: sign in (existing test account), capture a text
  note, see it appear in the grid; share-extension flow driven from Safari.
- Every phase ends with an XcodeBuildMCP build → simulator run → screenshot check.

## Phases

0. **Setup (Will):** connect XcodeBuildMCP (`claude mcp add XcodeBuildMCP -- npx -y xcodebuildmcp@latest`, restart session). Simulator dev needs no Apple team; device installs + TestFlight later need one (3 app ids + app group).
1. **Foundation:** scaffold workspace + StashKit, auth (sign in), View tab read path (grid, filters, realtime, detail read-only).
2. **Capture:** `add-file` function; capture sheet (text/URL/photos); Outbox; edit/delete/tags in detail.
3. **Share extension.**
4. **Voice notes + Ask tab.**
5. **Widgets + App Intents + settings/gates + polish → TestFlight.**

## Decisions (resolved by Will, 2026-08-10)

1. **Tabs:** Add · Ask · View · Settings, in that order — "View" is the library
   list. (Amended from the proposed Stash · Add · Ask · Settings.)
2. **v1 scope cuts** as listed in Non-goals: approved.
3. **`add-file` edge function:** approved.
4. **Repo location:** `ios/` folder in this repo: approved.

Also approved as recommended: server Whisper for voice notes, min iOS 17,
`stash://` scheme, `it.gostash.*` bundle ids, TestFlight before App Store.
