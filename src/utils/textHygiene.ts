// Text hygiene for titles and descriptions that arrive from scraped metadata.
//
// Sites ship og:title / og:description with HTML entities still encoded
// (Instagram: `&quot;` `&#x2019;`), sometimes twice (LinkedIn: `&amp;#39;`),
// and captions carry markdown emphasis markers (`**1. Terms**`). None of that
// is meaningful to a reader, so the platform decodes/strips it before storing
// and the clients decode again at render as a safety net for legacy rows.
//
// PAIRED FILE: supabase/functions/_shared/textHygiene.ts is the Deno copy of
// these pure helpers for the edge functions. Any change here must be made
// there too (and vice versa) — tests live in textHygiene.test.ts beside this
// file.

const NAMED_ENTITIES: Record<string, string> = {
  amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ',
  ndash: '–', mdash: '—', hellip: '…', lsquo: '‘', rsquo: '’', ldquo: '“', rdquo: '”',
  sbquo: '‚', bdquo: '„', laquo: '«', raquo: '»', bull: '•', middot: '·', prime: '′', Prime: '″',
  copy: '©', reg: '®', trade: '™', deg: '°', times: '×', divide: '÷', plusmn: '±',
  frac12: '½', frac14: '¼', frac34: '¾', euro: '€', pound: '£', yen: '¥', cent: '¢',
  larr: '←', rarr: '→', uarr: '↑', darr: '↓', hearts: '♥', iexcl: '¡', iquest: '¿', sect: '§', para: '¶',
  agrave: 'à', aacute: 'á', acirc: 'â', atilde: 'ã', auml: 'ä', aring: 'å', aelig: 'æ', ccedil: 'ç',
  egrave: 'è', eacute: 'é', ecirc: 'ê', euml: 'ë', igrave: 'ì', iacute: 'í', icirc: 'î', iuml: 'ï',
  ntilde: 'ñ', ograve: 'ò', oacute: 'ó', ocirc: 'ô', otilde: 'õ', ouml: 'ö', oslash: 'ø',
  ugrave: 'ù', uacute: 'ú', ucirc: 'û', uuml: 'ü', yacute: 'ý', yuml: 'ÿ', szlig: 'ß',
  Agrave: 'À', Aacute: 'Á', Acirc: 'Â', Atilde: 'Ã', Auml: 'Ä', Aring: 'Å', AElig: 'Æ', Ccedil: 'Ç',
  Egrave: 'È', Eacute: 'É', Ecirc: 'Ê', Euml: 'Ë', Igrave: 'Ì', Iacute: 'Í', Icirc: 'Î', Iuml: 'Ï',
  Ntilde: 'Ñ', Ograve: 'Ò', Oacute: 'Ó', Ocirc: 'Ô', Otilde: 'Õ', Ouml: 'Ö', Oslash: 'Ø',
  Ugrave: 'Ù', Uacute: 'Ú', Ucirc: 'Û', Uuml: 'Ü', Yacute: 'Ý',
};

const ENTITY_RE = /&(?:#[xX]([0-9a-fA-F]{1,6})|#([0-9]{1,7})|([A-Za-z][A-Za-z0-9]{1,31}));/g;

const decodeOnce = (text: string): string =>
  text.replace(ENTITY_RE, (match, hex?: string, dec?: string, name?: string) => {
    if (name !== undefined) return NAMED_ENTITIES[name] ?? match;
    const codePoint = hex !== undefined ? parseInt(hex, 16) : parseInt(dec as string, 10);
    if (!Number.isFinite(codePoint) || codePoint <= 0 || codePoint > 0x10ffff) return match;
    // Surrogate halves are not characters; leave the reference visible rather
    // than emit a lone surrogate
    if (codePoint >= 0xd800 && codePoint <= 0xdfff) return match;
    return String.fromCodePoint(codePoint);
  });

// Some sources encode already-encoded text (`&amp;#39;` → `&#39;` → `'`), so
// keep decoding while it still changes something — bounded so a pathological
// string can't loop.
export const decodeHtmlEntities = (text: string): string => {
  let current = text;
  for (let pass = 0; pass < 4; pass += 1) {
    const next = decodeOnce(current);
    if (next === current) break;
    current = next;
  }
  return current;
};

// Markdown emphasis markers wrapping a run of text: `**bold**`, `__bold__`,
// `*em*`, `_em_`, `` `code` ``. A single-sided marker (a bare `*` in math, a
// trailing footnote star, snake_case) is left alone.
const stripMarkdownEmphasis = (text: string): string =>
  text
    .replace(/\*\*(?=\S)([\s\S]+?)(?<=\S)\*\*/g, '$1')
    .replace(/__(?=\S)([\s\S]+?)(?<=\S)__/g, '$1')
    .replace(/(^|[\s(])\*(?=\S)([^*\n]+?)(?<=\S)\*(?=[\s).,;:!?]|$)/g, '$1$2')
    .replace(/(^|[\s(])_(?=\S)([^_\n]+?)(?<=\S)_(?=[\s).,;:!?]|$)/g, '$1$2')
    .replace(/`([^`\n]+)`/g, '$1');

// Full hygiene for a stored title/description: decode, drop emphasis
// markers, collapse whitespace.
export const cleanMetaText = (text: string): string =>
  stripMarkdownEmphasis(decodeHtmlEntities(text)).replace(/\s+/g, ' ').trim();

export const cleanOptionalMetaText = (value: string | null | undefined): string | undefined => {
  if (value === null || value === undefined) return undefined;
  const cleaned = cleanMetaText(value);
  return cleaned.length > 0 ? cleaned : undefined;
};
