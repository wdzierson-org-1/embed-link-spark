# Stash

Personal knowledge capture: save links, notes, photos, voice memos, and files
with the lowest possible friction; server-side enrichment (titles, transcripts,
OCR, summaries, embeddings, link flavor) makes everything findable. Deployed at
https://www.gostash.it (Vercel; push to `main` auto-deploys the web app).

## Read these before making product or capture/rendering changes

1. **`docs/ETHOS.md`** — the product compass: single-object capture, no
   collections, lowest-friction in, enrichment-as-a-service behind the platform
   API. Decisions not spelled out elsewhere get decided the way this points.
2. **`docs/ui-changes.md`** — cross-platform change log (newest first). Every
   meaningful UI/behavior change gets a dated, contracts-first entry so agents
   on the other platforms can mirror it without reverse-engineering. If you
   change behavior, add the entry in the same branch.
3. **`docs/PLATFORM_API.md`** — the wire contract every client builds on
   (`add-note` / `add-url` / `add-file`, chat SSE, realtime).

## Surfaces

- **Web** — `src/` (Vite + React + TS + shadcn; tests: `npm test`).
- **Chrome extension** — `extension/` (MV3, plain JS, no build step; load
  unpacked; tests: `cd extension && npm test`).
- **iOS** — `ios/` (SwiftUI app + `StashKit` Swift package; unit tests:
  `cd ios/StashKit && swift test`; specs/plans in `docs/superpowers/`).
- **macOS** — separate repo (`stash-mac`, menubar wrapper).
- **Backend** — `supabase/` (Postgres + edge functions; deploy via
  `supabase functions deploy <name>`, then verify with
  `supabase functions list` — an undeployed function surfaces as a CORS error).

## Data-model lanes (all platforms keep these clean)

`content` = the user's own words · `description` = the object's own/AI short
text · `page_body` = captured source material (scrapes, transcripts, OCR) ·
`summary` = long AI summary · `attributes` = structured facts (location, link
flavor, media metadata; whole-blob writes — preserve keys you don't model).
Never create `type='collection'` (legacy read-only). `posted_from` does not
exist.
