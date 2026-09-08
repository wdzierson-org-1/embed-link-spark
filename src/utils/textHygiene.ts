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

// --- Titles -----------------------------------------------------------------
//
// Social sites fold hashtags into og:title. A LinkedIn post that opens with a
// tag block ships a title that is nothing but tags ("#aiagents #opensource |
// André Lindenberg | 13 comments"); Instagram and TikTok captions end on a run
// of them. None of that reads as a card title. A tag here is `#` plus a letter
// at a word start, so `C#`, `#42` and `Issue #3` are left alone.
const TAG = '#\\p{L}[\\p{L}\\p{N}_]*';
const NOT_WORD_BEFORE = '(?<![\\p{L}\\p{N}_#])';
const NOT_WORD_AFTER = '(?![\\p{L}\\p{N}_])';
// Two or more tags in a row are a tag block wherever they sit ("#hiring #jobs
// We're looking…", "…Link in bio. #maven #ai", "…at home. #diy #decor @shop").
const TAG_BLOCK_RE = new RegExp(`${NOT_WORD_BEFORE}${TAG}(?:\\s+${TAG})+${NOT_WORD_AFTER}`, 'gu');
// A lone tag closing a segment — a closing quote or bracket may sit after it
// (Instagram wraps the caption in quotes).
const TRAILING_TAG_RE = new RegExp(`${NOT_WORD_BEFORE}${TAG}(?=\\s*["'”’)\\]]*\\s*$)`, 'u');
// Any lone tag left is prose ("#AI is changing work", "from #Stanford"): keep
// the word.
const INLINE_TAG_RE = /(?<![\p{L}\p{N}_])#(?=\p{L})/gu;
const EMPTY_QUOTES_RE = /"\s*"|“\s*”/g;
const SPACE_BEFORE_CLOSER_RE = /\s+(?=["”’)\]]\s*$)/;
const DANGLING_PUNCT_RE = /^[\s:;,|\-–—]+|[\s:;,|\-–—]+$/g;
// LinkedIn's engagement tail ("| 13 comments"); never a title on its own.
const COUNT_SEGMENT_RE = /^\d[\d,.]*[kKmM]?\s+(comments?|reactions?|likes?|reposts?)$/i;
const SEGMENT_SEPARATOR_RE = /\s+\|\s+/;
// Sentence end: . ! ? then whitespace — except after an initial ("Fabio A.
// recommended…") or a short abbreviation.
const SENTENCE_END_RE = /(?<=[.!?])(?<!\b\p{Lu}\.)(?<!\b(?:e\.g|i\.e|vs|etc|Dr|Mr|Mrs|Ms)\.)\s+/u;
const LEAD_MAX = 90;

const stripHashtags = (segment: string): string =>
  segment
    .replace(TAG_BLOCK_RE, '')
    .replace(TRAILING_TAG_RE, '')
    .replace(INLINE_TAG_RE, '')
    .replace(EMPTY_QUOTES_RE, '')
    .replace(/\s+/g, ' ')
    .replace(SPACE_BEFORE_CLOSER_RE, '')
    .replace(DANGLING_PUNCT_RE, '');

const capLead = (text: string): string => {
  if (text.length <= LEAD_MAX) return text;
  const cut = text.slice(0, LEAD_MAX);
  const lastSpace = cut.lastIndexOf(' ');
  return `${(lastSpace > LEAD_MAX / 2 ? cut.slice(0, lastSpace) : cut).trimEnd()}…`;
};

// First sentence of a post body, standing in for a lead that was only tags.
// A description that is itself just a URL (TikTok tag pages) is no lead.
const leadFromDescription = (description: string): string => {
  const body = stripHashtags(cleanMetaText(description));
  if (/^https?:\/\/\S*$/i.test(body)) return '';
  const sentence = body.split(SENTENCE_END_RE)[0] ?? '';
  return capLead(sentence.replace(/\.$/, '').trim());
};

// Title hygiene: everything cleanMetaText does, then hashtags out of every
// ` | ` segment, the engagement tail dropped, and a tags-only lead replaced
// by the first sentence of `description` (the post body) when one is known.
export const cleanMetaTitle = (title: string, description?: string | null): string => {
  const rawSegments = cleanMetaText(title).split(SEGMENT_SEPARATOR_RE);
  const segments = rawSegments.map(stripHashtags);
  const leadWasTags = segments[0] === '' && /#\p{L}/u.test(rawSegments[0]);
  const kept = segments.filter((segment) => segment !== '' && !COUNT_SEGMENT_RE.test(segment));
  if (leadWasTags && description) {
    const lead = leadFromDescription(description);
    if (lead) kept.unshift(lead);
  }
  return kept.join(' | ');
};

export const cleanOptionalMetaTitle = (
  title: string | null | undefined,
  description?: string | null,
): string | undefined => {
  if (title === null || title === undefined) return undefined;
  const cleaned = cleanMetaTitle(title, description);
  return cleaned.length > 0 ? cleaned : undefined;
};
