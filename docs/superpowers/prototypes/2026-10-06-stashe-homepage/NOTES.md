# Stashe homepage — exploration v0.1 (2026-10-06)

Open `../2026-10-06-stashe-homepage.html` from a repo checkout, or serve the repo root
(`python3 -m http.server 8090`) and visit
`http://localhost:8090/docs/superpowers/prototypes/2026-10-06-stashe-homepage.html`.

## The brief (Will, 2026-10-06)

Rename to **Stashe** (domain `stashe.it`). Start from typesafe.ai's DIY/retro register, but
the app itself is not retro: show screenshots of an app direction that is clean and unfussy
with hints of DIY. Keep the basics: an ASCII-animation hero in purple or lime; a plain
statement of the use case with a paste → enrichment animation; MCP with a "Works with" logo
row and why enrichment matters there; "take your saves with you"; phone saving through the
share sheet; "Stashe is smarter saving." Try the React Bits Pro effects (Liquid Ascii,
Device, Pixelate Hover, Halftone Wave).

## The idea: clean objects, DIY machinery

typesafe.ai's look is pixel-OS windows, crop marks, black mono tags, dither fields and huge
grotesk headlines. Stashe takes that vocabulary but gives it a job:

- **Clean** is everything that belongs to the person: the things they saved (cards, photos,
  their notes). White surfaces, PP Neue Montreal, soft 12–14px corners.
- **DIY** is everything Stashe does for them: enrichment, processing, metadata, connections.
  That is the "machine voice": Departure Mono in black tags, square windows with black title
  bars, ASCII, dither, dotted-leader receipts.

So the DIY never decorates; it marks where the machine is working. That is also how it
carries into the app: the library screenshot is calm and plain, and the only pixel type is in
the tags, the "| reading…" processing states and the "gathered" receipt.

Print logic: paper `#f3f4f1`, black ink, one spot colour. **Lime** `#a3f53b` (the Signal green
from the fieldnotes studies) is the default; **violet** `#6d5bd0` (today's brand violet) is the
alternative. On lime the ink is black; on violet it flips to white.

## Page

1. **Hero — "Save first. Ask later."** The stash as a tank of liquid drawn in ASCII. Saved
   things (tags: a TikTok URL, a screenshot filename, an arXiv link…) are tossed in and sink.
   Pointer stirs, click splashes or tosses, and pasting a link anywhere on the page drops it in.
   A soft lid under the copy keeps a wild stir from burying the headline.
2. **"You save anything — a link, a screenshot, an article, a paper, a TikTok. We gather all of
   the background."** The words are the controls. Each plays its own example: paste → card
   arrives as dither and resolves as Stashe reads it → enrichment windows pop out on leader
   lines → the payoff, "find it by", in the spot colour. On phones the windows become an ASCII
   tree under the card.
3. **"All of it, in one calm place."** A full library screenshot: the proposed web-app
   direction (masonry of clean cards, one open in a detail panel with a dotted-leader
   "gathered" receipt). Re-flows to a phone-sized window under 700px rather than shrinking.
4. **"Your stash, inside every AI you use."** typesafe-style windows on a lime dither panel:
   Claude answering from a TikTok's transcript, Claude Code finding a saved repo. Three
   points (not just links / found by meaning / read-only), then **Works with**: Claude,
   ChatGPT, Hermes, Cursor, Zed, Claude Code, Codex, Gemini CLI, VS Code, Windsurf, Goose,
   Raycast, plus the `stashe.it/mcp` connector address.
5. **"Take your saves with you."** Will's copy, verbatim in spirit. The repo, the bag and the
   moodboard are fuzzy (pixelated) memories that come into focus under a lens; each has a
   receipt of where it came back (Cursor, the phone in a shop, Claude).
6. **"Saving takes one tap."** A CSS iPhone (tilts toward the pointer) runs three real-feeling
   share-sheet saves: four screenshots from Photos, a photo of a book's cover, a Medium article
   from Safari. Then the library with the new saves arriving.
7. **"Stashe is smarter saving."** Lime field, halftone knocked out around the type like a
   print knockout.

## Effects (React Bits Pro, re-implemented)

The Pro components are licence-gated (the docs show props, not source) and React 19/Tailwind
4/`motion`, which the Vite app can't import directly (see the reactbits-pro memory). Each one
here is written from scratch in plain JS with the same parameters, so the look can be judged
now and the licensed component swapped in later if it's chosen.

| React Bits Pro | Here | File |
|---|---|---|
| Liquid Ascii | FLIP fluid (after Ten Minute Physics), ASCII by density, motion and depth | `js/liquid.js` |
| Pixelate Hover | Stepped lens of finer blocks (not a crossfade); also the card's resolve | `js/pixel.js` |
| Halftone Wave | FBM value-noise dot field with a knockout; still dot clouds in the AI panel | `js/halftone.js` |
| Device | CSS iPhone with pointer tilt | `js/phone.js` |

All animation pauses offscreen and in hidden tabs. `prefers-reduced-motion` gets complete,
static frames: a settled tank, the final enrichment frame, the share sheet. The two loops
(enrichment, phone) have pause buttons.

## Deep links

`#spot=violet` · `#ex=link|shot|article|paper|tiktok` · `#scene=shots|book|article|library` ·
`#still` freezes every animation on a representative frame (used for the renders). After
changing only the hash, reload the page.

## Sources and licences

- **Departure Mono** (Helena Zhang), SIL OFL 1.1: `fonts/DepartureMono-Regular.woff2` with
  `fonts/DepartureMono-LICENSE.txt`. PP Neue Montreal is the repo's existing licensed copy.
- **Logos**: LobeHub icons (`@lobehub/icons-static-svg`, MIT) and Simple Icons (CC0) for Zed,
  VS Code and Raycast. Inline, one colour. These are trademarks of their owners. Using them on
  a live page needs the usual care; check each brand's guidelines before shipping.
- **Photos**: Unsplash (free licence), by photo id: `bag.jpg` = photo-1598532163257,
  `mood-tile.jpg` = photo-1702014861373, `mood-travertine.jpg` = photo-1648639035105,
  `mood-kitchen.jpg` = photo-1585128833500, `mood-leather.jpg` = photo-1637759292654.
  The four landing covers come from `src/assets/landing/`.
- **Composed samples** (`asset-src/*.html` → `img/` via `sh asset-src/build.sh`): the moodboard,
  a phone screenshot of a social post, the first page of a paper, and a repo plate.

## Real vs illustrative

Real: `charmbracelet/gum` (description, Go, MIT, `brew install gum`, `gum choose`,
`gum confirm`); the paper *Lost in the Middle* (Liu et al., arXiv 2307.03172, July 2023;
its authors and the U-shaped finding). Illustrative: Chez Colette, @chez.colette,
@sundaysupper, Ada Whitlock / Notes on Reading, every transcript, quote, note, price and
timestamp. The paste interaction splashes; nothing is saved.

## Open questions for Will

1. **Name:** the brief says "Stache" once and "Stashe" twice; the domain is `stashe.it`.
   This uses **Stashe**, with a "stashe.it" wordmark where ".it" is set in the pixel face.
2. **Lime or violet** for the spot colour (toggle bottom-right).
3. **Claims to confirm before any of this ships:** TikTok transcripts and on-screen text,
   reading every page of a PDF, and the "Works with" list (memory has Claude Code `/mcp`
   auth still open). The MCP copy says read-only and "you approve each app", which matches
   the shipped server.
4. Does the **library screenshot** (section 3) belong on the homepage, or is it the start of
   the web-app redesign brief?
5. Typesafe uses title case and a pixel face for body labels. This keeps sentence case, and
   uses the pixel face only for the machine voice.
