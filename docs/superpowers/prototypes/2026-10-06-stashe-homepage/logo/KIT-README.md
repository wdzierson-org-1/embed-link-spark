# ST4SH wordmark concept

An uppercase STASH wordmark for **st4sh.app**, using **PP Mori Semibold** with a custom A/4 hybrid.

## Design

The middle character retains the left diagonal and baseline foot of an A. An upright right stem and a crossbar extending beyond it introduce the 4. The custom glyph shares the font's 700-unit cap height and approximately 120-unit upright stroke. Spacing is optically adjusted for the five-letter lockup.

- Primary color: charcoal `#171B1A`
- Reversed color: warm white `#F3F2EE`
- Suggested clear space: at least half the cap height on every side.
- Use the separate A/4 icon where the full wordmark would be too small.
- Accessible name: **STASH**. The domain is **st4sh.app**.

## Files

| File | Purpose |
| --- | --- |
| `st4sh-wordmark.svg` | Transparent charcoal wordmark; editable vector paths |
| `st4sh-wordmark-light.svg` | Transparent warm-white wordmark for dark surfaces |
| `st4sh-wordmark.png` | Transparent 2400 px PNG export |
| `st4sh-symbol.svg` | Standalone A/4 monogram |
| `st4sh-app-icon.svg` / `.png` | Charcoal app icon; PNG at 512 × 512 |
| `favicon.svg` / `.ico` | Browser icon; ICO includes 16, 32, and 48 px sizes |
| `st4sh-preview.svg` / `.png` | Concept presentation sheet |
| `build_logo.py` | Editable geometry and export script |

All SVG lettering is converted to paths. The exports contain no embedded font, remote resource, or script, and render without PP Mori installed.

## Typeface source and production use

This is a local design concept created from the [official PP Mori specimen](https://pangrampangram.com/products/mori), retrieved on September 21, 2026. No font binary is included in this folder.

Pangram Pangram permits personal testing and client pitches under its free-to-try terms, and specifies a **Logo license** for commercial company logos. Confirm the appropriate license before using this concept publicly. [Foundry FAQ](https://pangrampangram.com/pages/faq)

## Regeneration

Supply your own appropriately licensed PP Mori variable font or Semibold style:

```sh
python3 -m pip install 'fonttools[woff]'
python3 brand/build_logo.py --font /path/to/PPMori-Variable.ttf
```

The script produces SVGs only. PNGs and the ICO are raster exports of those SVGs. The `A4` path and `POSITIONS` constants control the custom character and spacing.
