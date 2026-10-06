# Stash homepage — exploration v0.3 (2026-10-06)

Open `../2026-10-06-stashe-homepage.html` from a repo checkout, or serve the repo root
(`python3 -m http.server 8090`) and visit
`http://localhost:8090/docs/superpowers/prototypes/2026-10-06-stashe-homepage.html`.
(The folder keeps its v0.1 "stashe" name so the history stays in one place.) The footer pages
sit in this folder: `extension.html`, `mcp.html`, `iphone.html`.

## v0.3: Will's round 3

| Ask | What changed |
|---|---|
| Texture in the hero, like typesafe's but subtler | A static layer behind the pool (`.hero-tex`, drawn in `js/liquid.js`), after the dithered desktop on typesafe.ai: a fine 4 px dot grid and three stippled spheres lit from the top right, ordered-dithered at about a quarter of typesafe's ink. It fades out above the waterline so the glyphs stay clean, and it is redrawn on resize and on the lime/violet switch. |
| Hold each link half a second before it drops; a `link:` label | Every save now appears labelled with its kind (`link: medium.com/…`, `place: Chez Colette`, `voice memo: 0:42`, with the kind in the spot colour). It hangs about 0.56 s, breathing a pixel or two, then drops from rest; gravity is a little gentler. |
| Images (square, low-res); places, book covers, papers | Pictures drop as 18×18 tiles shown at 4 px a pixel, above their label. Photos are shrunk from real images (bag, the TikTok pasta, a screenshot, the moodboard, a Lisbon courtyard). A place, a paper and a book are pixel art drawn in code: a street map with a route and pin, a two-column arXiv page, and the *Walden* cover. Saves hang only where the sky is clear: the copy is measured line by line, so at 1440×900 pictures appear in the gap between the headline and the lead. On phones there's no clear sky, so only clicks drop saves (as in v0.2). |
| The droplet effect only in the ASCII, no halo above the sea | The radial glow is gone. A landing sends concentric neon rings through the glyphs themselves, and as each ring fades its glyphs dissolve back to ink one by one. The ripple exists only where the pool is. The decrypting band now opens with the same label as the drop (`link: medium.com/… >> article about…`). |
| Headline "Save it fast. Find it when you need it." | Set on three lines at `clamp(50px, 8vw, 128px)`, with the pool 2 points lower (fill 0.35) to keep the sky. The lead loses its echo of "find it": "…so later you can ask about it in your own words and take it anywhere." |
| A small subtitle "STASH ENRICHES YOUR ITEMS AUTOMATICALLY" | A black machine-voice tag above the statement, set in capitals as asked. |
| The card picture stays the same whatever you drop in (DESIGN.md showed the gum repo) | Root cause: the card's canvas was never cleared between runs, and an image arriving late from an earlier run could still paint over a newer one. Every run now starts from a blank frame, with a run guard. A link gets **0.75 s** for its real og:image. After that a placeholder for the kind of thing it is stands in: a pixel glyph for page, article, video, repo, book, social or place on the spot colour, plus the site's favicon and domain. If the og:image does arrive later, it pixel-resolves over the placeholder, which first gets 0.55 s on screen so the swap doesn't flicker. A text or Markdown file shows a page made from **its own first lines**. A PDF shows a page that takes the PDF's own title when the endpoint finds one (that title now stays as the card title, and the file size is no longer wiped). |
| Fill the phone video with realistic content | The grey-bar screenshots are now real iOS screenshots, composed in `asset-src/` and rendered to `img/shot-*.jpg`: Apple Maps directions to Chez Colette, a Threads post on keeping a sourdough starter, a Mail receipt for $6.50, a Wallet boarding pass (BOS → SFO), and a Messages thread that ends "i'll screenshot it". They fill the Photos grid alongside real photos, appear in the share-sheet and save-panel thumbnails, and appear in the library cards. The book is photographed on a café table with a latte (`img/table-latte.jpg`, Unsplash), and its shadow falls the way the window light does. |
| Footer: Chrome extension page (redesigned), MCP page, iPhone placeholder with a notify sign-up in its own column, contact/terms/privacy in their own column | The footer has columns: the brand; **set up** (Chrome extension, Connect your AI (MCP)); **iphone app** (a link to its page and an inline "Notify me" field); **company** (Contact, Terms, Privacy). There are three new pages in the same system: **`extension.html`**, the live install page's facts redrawn (a drawn browser with the pinned Stash it badge and the right-click menu, six numbered steps, three ways to save, updating); **`mcp.html`**, with the server URL to copy, steps for Claude, ChatGPT, Claude Code, Cursor, VS Code and everything else, the real tools, and the read-only, approve-each-app and every-request-logged guarantees; and **`iphone.html`**, what it does plus a big Notify me form and a phone picture rendered from the homepage's own CSS iPhone. The sprite, nav, footer and review panel live once in `js/site.js`, so the four pages can't drift. |

Verified in v0.3 (Playwright at 1440×900 and 390×844, lime, violet and reduced motion; no page errors):
- `DESIGN.md` → page preview with its first lines, "doc" tag, the size, and the model's title.
- paulgraham.com essay (no og:image) → page glyph, favicon and domain.
- github.com/pbakaus/impeccable → the placeholder at 0.75 s, then the real card resolving over it.
- No horizontal overflow on any page at 390 px.

Testing used 4 calls of the IP's 15-per-10-minutes allowance on `homepage-enrich`.

## v0.2: Will's round 2

| Ask | What changed |
|---|---|
| Use the logo assets; back to **Stash** | The ST4SH kit (`logo/`, from `st4sh-logo-concept.zip`) is an SVG sprite: wordmark in the nav, footer, phone and save panel; the A/4 symbol is the Stash app icon in the share sheet and the tool-call mark in Cursor and Claude. Copy says Stash everywhere. |
| $4.99/month, no free trial | "Get Stash" CTAs; "$4.99 a month". No trial copy anywhere. |
| Slower, cooler "paste a link" component with rounded lines | Leader lines have rounded elbows (S-curves for small offsets) with a spark that travels each line as it draws; values decrypt in; examples run ~30% slower. |
| Make it live UI, with instruction lines and an up-arrow Send | Focusing the composer stops the examples, lifts the field with a spot-colour ring and shows "Give it a try! Paste a link, drop in an image, or add a doc (under 2 MB) and watch the enrichment:". Once something is in, that line rises and fades and "Now press [↑] to watch this link/image/doc/note get more valuable" replaces it; the arrow is the Send button (aria-label "Send"). Paste, type, "+" to attach, or drag a file onto the stage. |
| Hook up the real enrichment API, as fast as possible | New edge function **`homepage-enrich`** (see below), wired in `js/api.js`. Results are disclosed as they stream: the page's own facts in ~0.5–2 s, then the model's findings one window at a time, then "Gathered in N s". |
| Park the app screenshot | Removed (v0.1 is in git at `f60a8a8a`). |
| AI section: Cursor-like and Claude-like, animated | Two tabs over the dither panel. Cursor: three panes after cursor.com's own window; the agent finds **pbakaus/impeccable** (real) in Stash and applies a red/green diff to `PricingCard.tsx`. Claude: a trip-planning chat that pulls three saved Lisbon hotels (illustrative names) and answers in Claude's serif. |
| Move "Saving takes one tap" under "try it" | Done. |
| Tighten the phone, fix occlusions | Real status bar (signal, Wi-Fi, battery) and home indicator; an opaque status-bar cover in Safari so the scrolled "Medium" header can't collide; iOS-style share sheet (grabber, close button, recognisable app icons, Stash = the A/4 icon); a Photos viewer bar. Kept as live HTML rather than video: it stays crisp at any size and can still be recorded later. |
| More duotone at the bottom | Denser halftone, plus the ST4SH wordmark set in dots across the bottom band (rendered from the logo's own paths). |
| Slower hero; the pool reacts | Pool at 80% speed, gentler and rarer tosses. Each landing sends neon concentric rings through the pool (glow + tinted glyphs), then a black band decrypts what Stash found: e.g. `medium.com/how-to-remember-more >> article about memory and retention with practical tips >> 2 minute read >> author: garret how >>`. **Paste any link on the page** and the band fills with the real enrichment from `homepage-enrich` as it streams. |

## The live endpoint: `supabase/functions/homepage-enrich`

Deployed to production (project `uqqsgmwkvslaomzxptnp`, `verify_jwt = false`), committed in
`4826d2bb`. Public and stateless: nothing is stored.

- **Input** (JSON POST): `{url}`, `{text}` (a note), or `{file: {name, type, data}}` for a JPG/PNG/WebP/GIF,
  PDF or text file up to 2 MB.
- **Output**: Server-Sent Events `start` → `meta` (page/oEmbed/GitHub) → `field {k,l,v}` … → `done {ms, firstField, model}`.
- **Fast path**: metadata straight from the page (or TikTok/YouTube oEmbed, the GitHub API), page text via
  the shared `htmlToText`; walled hosts race a crawler-UA fetch against the Jina reader; PDFs are read with
  `unpdf` (page count + title come from the file). Then ONE call to **gpt-4.1-nano** (fallback gpt-4o-mini)
  over Chat Completions, streamed; a brace-matching scanner emits each finding the moment its JSON object closes.
- **Measured on prod** (first field = first model finding): GitHub repo meta 0.67 s, done ≈ 2.5–4 s;
  essay 0.55 s / 1.4 s / 2.5 s; Medium (Karpathy) meta 0.76 s, done 3.6 s; image done ≈ 2 s; note ≈ 2 s;
  18-page PDF done ≈ 4 s. Chat Completions beat the Responses API by ~0.6 s to first finding.
- **Guards**: http(s) public hosts only (no IP literals in private ranges, no odd ports, redirects
  re-checked), 1.5 MB page cap, body read before any reply. Admission through
  `homepage_enrich_admit` (migration `20261006150000`, applied + recorded): salted IP hash only;
  15 per 10 min and 60 per day per IP, 400 per hour overall; RLS on, service role only.
  Verified: private/metadata/loopback/file URLs refused, HEIC/oversize refused, CORS only echoes
  gostash.it / st4sh.app / localhost, the burst cap trips at 15.
- **Cost bound**: ≤ 400 calls/hour × a fraction of a cent (nano, ≤ 640 output tokens).
- Found while testing: `JINA_API_KEY` is **not set** in production, so the reader runs on Jina's free
  tier (fine for Medium in ~0.3 s; The Verge takes 7–12 s, so the demo gives the reader 9 s).

## The idea (unchanged): clean objects, DIY machinery

Anything that is the person's own stays clean (cards, photos, their words: Neue Montreal, white,
soft corners). Anything Stash does for them speaks in the machine voice (Departure Mono in black
tags, square windows, ASCII, dither, decrypting text). Print logic: paper `#f3f4f1`, black ink, one
spot colour, lime `#a3f53b` by default, violet `#6d5bd0` on the toggle.

## Page

1. **Save it fast. Find it when you need it.** Liquid-ASCII pool on a stippled sheet; labelled saves (and picture
   tiles) hang, then drop; rings through the glyphs; decrypted findings; paste anything.
2. **Stash enriches your items automatically / You save anything… We gather all of the background.** Example
   loop by word; live composer with honest card pictures.
3. **Saving takes one tap.** CSS iPhone: four screenshots, a book cover, a Medium article, then the library.
4. **Your stash, inside every AI you use.** Cursor / Claude tabs; three points; Works with (12 clients); `gostash.it/mcp`.
5. **Take your saves with you.** Pixel-reveal memories (repo, bag, moodboard).
6. **Stash is smarter saving.** Halftone close with the dotted wordmark, then the column footer.

Footer pages, same system, same close: `extension.html` (install Stash it in Chrome), `mcp.html` (connect your
AI), `iphone.html` (in beta; Notify me).

## Deep links

`#spot=violet` · `#ex=link|shot|article|paper|tiktok` · `#scene=shots|book|article|library` ·
`#ai=cursor|claude` · `#still` (freezes everything on a representative frame, used for the renders).
Reload after changing only the hash. The footer pages take `#spot=violet` too.

## Sources and licences

- **ST4SH logo kit** (`logo/`, kit README as `logo/KIT-README.md`): outlined PP Mori Semibold lettering.
  The kit itself notes that public use of a PP Mori–based logo needs Pangram Pangram's **logo licence**.
- **Departure Mono** (Helena Zhang), SIL OFL 1.1, with its licence in `fonts/`.
- **Logos** in Works with and the tabs: LobeHub icons (MIT) and Simple Icons (CC0); trademarks of their owners.
- **Photos**: Unsplash (free licence). `bag.jpg` photo-1598532163257, `mood-tile.jpg` photo-1702014861373,
  `mood-travertine.jpg` photo-1648639035105, `mood-kitchen.jpg` photo-1585128833500,
  `mood-leather.jpg` photo-1637759292654, `hotel-courtyard.jpg` photo-1776083928944,
  `hotel-rooftops.jpg` photo-1704908325704, `hotel-garden.jpg` photo-1654482278660, `table-latte.jpg`
  photo-1636875485729 (v0.3, the café table under the book); landing covers from `src/assets/landing/`.
- **Composed samples** (`asset-src/*.html` → `img/` via `sh asset-src/build.sh`): moodboard, social-post
  screenshot, paper first page, repo plate, and (v0.3) the five phone screenshots `shot-maps`, `shot-thread`,
  `shot-receipt`, `shot-boarding`, `shot-messages` (390×844, JPEG). The QR code is decorative.
- **Pixel art** in the hero's picture tiles (map, arXiv page, *Walden* cover) is drawn in code in `js/liquid.js`.
- **`img/iphone-share.png`** is rendered from the homepage's own CSS iPhone (`#still&scene=shots`, phone at 1.48×,
  outer shadow off, transparent background) for `iphone.html`; re-render it if the phone changes.

## Real vs illustrative

Real: `charmbracelet/gum`, `pbakaus/impeccable` (description quoted from GitHub), *Lost in the Middle*
(Liu et al., arXiv 2307.03172, 18 pages), and everything the live endpoint returns. Illustrative: Garret How,
Chez Colette, @sundaysupper, the Lisbon hotels (Casa do Pátio, Miradouro 22, Jardim Escondido), every
note, price, date and transcript in the scripted examples, and in the v0.3 screenshots @breadbykat,
@flourpowerdan, Maya, Alex Morgan, the airline "Northline", and the map's Hollis Books, Little Fern and
Marlow & Co. **Blue Bottle Coffee is a real business**, named on the receipt and in a library card (it was in
v0.2's card too); swap in an illustrative café before anything ships. The street address is real.

## Open questions for Will

1. **Domain:** the kit says st4sh.app; the product and MCP endpoint are gostash.it. The page shows
   `gostash.it/mcp` (true today). Which should the homepage use?
2. **PP Mori logo licence** before the wordmark goes public.
3. **Lime or violet.**
4. **Endpoint limits:** 15/10 min and 60/day per IP, 400/hour overall. Right for launch traffic? To turn the
   demo off: `supabase functions delete homepage-enrich`; the caps live in `homepage_enrich_admit`.
5. **Claims to verify before shipping:**
   - The scripted examples imply TikTok transcripts and on-screen text.
   - Works with lists clients we haven't all tested.
   - On `mcp.html`, three client steps are untested: ChatGPT's Developer-mode path (from `docs/mcp/DIRECTORIES.md`), Claude Code's "open /mcp to sign in", and Cursor prompting sign-in on first use.
   - On `iphone.html`, the iOS beta needs to do what the page says, including Ask with sources and sharing from the camera.
6. **Contact address.** v0.2's footer used hello@gostash.it, which exists nowhere in the repo. v0.3 uses
   will@dzierson.com, the address the live landing and legal pages use. Do you want a hello@ address instead?
7. **"Notify me" is not wired.** There's no list behind it, so the form validates the address and then says
   "prototype: not sent". It needs a home, for example a small table and edge function, or a Resend audience,
   since Resend already sends the reminder email.
8. **The live extension page** (`public/extension/index.html`, unlisted at gostash.it/extension) is untouched.
   `extension.html` is its redesign in this direction. Port it when a direction is picked, keeping
   `extension/scripts/publish-hosted-zip.sh` in charge of the version and size (copied here as 1.2.1, 33 KB).
9. Your round-2 note ended at "maybe we could pick a" — what was the rest?
