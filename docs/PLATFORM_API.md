# Stash platform API

The contract for every Stash client — web app, chat mole, menubar widget,
browser extension, iOS. All capture and retrieval intelligence lives server-side
in Supabase edge functions; clients stay thin and platform-independent.

Base URL: `https://uqqsgmwkvslaomzxptnp.supabase.co/functions/v1`

## Auth

Every request sends two headers:

```
Authorization: Bearer <user JWT (session access_token)>
apikey: <anon key>
```

Get a JWT with supabase-js (`auth.signInWithPassword` / OAuth) on any platform,
or the raw REST endpoint `POST /auth/v1/token?grant_type=password`. The item
owner is always derived from the JWT server-side — never sent by the client.

## Capture

### `POST /add-url` — save a link

```json
{ "url": "https://…", "content": "optional note about it", "is_public": false }
```

Returns `{ success, item }` fast (title/description from a quick fetch).
Everything else continues server-side after the response: deep metadata with
the blocked-site rescue cascade (crawler UA → Jina Reader → Wayback → URL
inference), preview image storage, full-page scrape into `page_body`, and
embeddings. Clients never wait on enrichment — realtime (below) delivers the
upgrades.

`tags: …` at the end of `content` becomes item tags.

### `POST /add-note` — save a text note

```json
{ "content": "the note", "title": "optional", "is_public": false }
```

Returns `{ success, note }` immediately with a derived title; AI title +
description + re-embed land asynchronously.

Files (images, PDFs, audio) currently upload via Supabase Storage
(`stash-media/<userId>/…`) + a client-side insert — a `POST /add-file`
wrapper is the intended next step for parity.

## Ask

### `POST /chat-with-all-content` — streaming Q&A over the user's stash

```json
{ "message": "…", "conversationHistory": [{ "role": "user"|"assistant", "content": "…" }] }
```

Responds with Server-Sent Events:

```
data: {"delta":"token"}          ← repeatedly
data: {"done":true,"sources":[{"id","title","type","url"}]}
```

Retrieval is hybrid (pgvector + full-text, RRF-fused); sources are exactly the
items used in the answer's context. History is capped server-side at 6 turns.

## Message routing convention (chat surfaces)

Chat composers double as capture surfaces. Shared client contract
(`src/utils/moleRouting.ts` is the reference implementation):

- message contains a URL → `add-url` (surrounding text = the note)
- `remember:` / `save:` / `note:` prefix → `add-note`
- anything else → `chat-with-all-content`

## Live updates

Subscribe to Postgres changes to reflect async enrichment without polling:

```js
supabase.channel(`items-${userId}`)
  .on('postgres_changes',
      { event: '*', schema: 'public', table: 'items', filter: `user_id=eq.${userId}` },
      handler)
  .subscribe()
```

## Other channels

- WhatsApp/SMS: Twilio webhook (`/twilio-webhook`, Twilio-signature-verified);
  registration via `user_phone_numbers`.
- Public feeds: `GET /get-public-feed/<username>`, `GET /get-discover-feed`
  (anon key works for both).

## Notes for future clients

- Menubar widget / extension: `add-url` + `add-note` are sufficient for v1
  capture; JWT can be obtained via a one-time device sign-in with supabase-js.
- Voice: the web app uses the Web Speech API client-side and sends the final
  transcript through the normal chat routing; `/transcribe-audio`
  (Whisper) exists for platforms without native speech recognition.
