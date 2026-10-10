import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
const adapters = vi.hoisted(() => ({ html: vi.fn(), jina: vi.fn(), wayback: vi.fn() }));
vi.mock('./blockedContentFallbacks.ts', () => ({
  CRAWLER_UA: 'test-crawler',
  fetchHtml: adapters.html,
  fetchViaJinaReader: adapters.jina,
  fetchViaWayback: adapters.wayback,
  htmlToText: (html: string) => html,
}));
import { extractPage } from './pageExtraction';

const youtube = 'https://www.youtube.com/watch?v=YGgNBcIgI4s';
const article = 'https://example.com/tomatoes';
const footer = '- YouTube About Press Copyright Contact us Creators Advertise Developers Terms Privacy Policy & Safety How YouTube works Test new features NFL Sunday Ticket &copy; 2026 Google LLC';
const transcriptMarkdown = `# Tomatoes\n\n**Uploaded by**: [Chef](https://www.youtube.com/@chef)\n**Length**: 2:30\n\n## Description\n\n\`\`\`\nA quick salad.\n\`\`\`\n\n## Transcript\n\n[00:00] Pick ripe tomatoes, salt them,\n[00:04] and finish with olive oil.\n`;

const firecrawl = (markdown: string | null, status = 200) =>
  vi.fn().mockResolvedValue(new Response(JSON.stringify({ data: { markdown } }), { status }));

beforeEach(() => {
  vi.clearAllMocks();
  adapters.html.mockResolvedValue(footer);
  adapters.jina.mockResolvedValue({ content: footer });
  vi.stubGlobal('fetch', firecrawl(footer));
});
afterEach(() => vi.unstubAllGlobals());

describe('a YouTube video (spec 2026-09-05)', () => {
  it('is its transcript, read from Firecrawl v2 in English, with the video’s own facts', async () => {
    vi.stubGlobal('fetch', firecrawl(transcriptMarkdown));
    const capture = await extractPage(youtube, 'test-key');
    expect(capture).toMatchObject({
      kind: 'transcript',
      source: 'firecrawl-youtube',
      text: 'Pick ripe tomatoes, salt them,\nand finish with olive oil.',
      facts: { description: 'A quick salad.', durationS: 150, author: 'Chef' },
    });
    const [calledUrl, init] = (fetch as unknown as { mock: { calls: [string, RequestInit][] } }).mock.calls[0];
    expect(calledUrl).toBe('https://api.firecrawl.dev/v2/scrape');
    // A fresh scrape: Firecrawl's cache holds the plain watch page, without the transcript
    expect(JSON.parse(init.body as string)).toMatchObject({ url: youtube, formats: ['markdown'], onlyMainContent: true, location: { languages: ['en'] }, maxAge: 0 });
    expect(adapters.html).not.toHaveBeenCalled();
    expect(adapters.jina).not.toHaveBeenCalled();
  });

  it('writes nothing when Firecrawl has no transcript — and never falls back to the chrome', async () => {
    expect(await extractPage(youtube, 'test-key')).toBeNull();
    expect(adapters.html).not.toHaveBeenCalled();
    expect(adapters.jina).not.toHaveBeenCalled();
    expect(adapters.wayback).not.toHaveBeenCalled();
  });

  it('writes nothing without a Firecrawl key, without asking anyone', async () => {
    expect(await extractPage(youtube, undefined)).toBeNull();
    expect(fetch).not.toHaveBeenCalled();
    expect(adapters.jina).not.toHaveBeenCalled();
  });

  it('survives a Firecrawl failure', async () => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new Error('timeout')));
    expect(await extractPage(youtube, 'test-key')).toBeNull();
  });
});

describe('short-form video (Will, 2026-10-10)', () => {
  const tiktok = 'https://www.tiktok.com/@geodesaurus/video/7694829447538576670';
  const reel = 'https://www.instagram.com/reel/DdzpI9os_Wg/';
  const byUrl = (answers: Record<string, unknown>) =>
    vi.fn(async (input: string | URL | Request) => {
      const key = Object.keys(answers).find((prefix) => String(input).startsWith(prefix));
      return new Response(JSON.stringify(key ? answers[key] : { error: 'unexpected' }), { status: key ? 200 : 500 });
    });

  it('a TikTok is its transcript from SearchApi, with the language', async () => {
    vi.stubGlobal('fetch', byUrl({ 'https://www.searchapi.io/': { transcripts: [{ text: 'A dinosaur fact.' }, { text: 'Another one.' }], available_languages: [{ lang: 'en', is_selected: true }] } }));
    expect(await extractPage(tiktok, { tiktok: 'tk', firecrawl: 'fc' })).toMatchObject({ kind: 'transcript', source: 'searchapi-tiktok', text: 'A dinosaur fact.\nAnother one.', facts: { language: 'en' } });
    expect(adapters.html).not.toHaveBeenCalled();
  });

  it('a Reel is its transcript from TranscriptFetch, with the caption as its description', async () => {
    vi.stubGlobal('fetch', byUrl({ 'https://transcriptfetch.com/': { ok: true, data: { text: 'An asteroid might get interesting.', language: 'en', title: 'Asteroid watch', duration: 38.6 } } }));
    expect(await extractPage(reel, { reels: 'rf' })).toMatchObject({ kind: 'transcript', source: 'transcriptfetch-instagram', facts: { description: 'Asteroid watch', durationS: 39, language: 'en' } });
  });

  it('without a key, or without a transcript, a social video falls through to the cascade as before', async () => {
    adapters.html.mockResolvedValue('');
    adapters.jina.mockResolvedValue({ content: 'A long enough caption to count as usable page text for this video post.' });
    expect(await extractPage(tiktok, { firecrawl: undefined })).toMatchObject({ source: 'jina-reader' });
    vi.stubGlobal('fetch', byUrl({ 'https://www.searchapi.io/': { transcripts: [] } }));
    expect(await extractPage(tiktok, { tiktok: 'tk' })).toMatchObject({ source: 'jina-reader' });
  });
});

describe('any other page', () => {
  it('takes Firecrawl v2 markdown when it is usable', async () => {
    vi.stubGlobal('fetch', firecrawl('Pick ripe tomatoes, salt them, and finish with olive oil. A longer article follows here.'));
    expect(await extractPage(article, 'test-key')).toMatchObject({ source: 'firecrawl', kind: 'page' });
    expect(adapters.html).not.toHaveBeenCalled();
    // Ordinary pages may come from Firecrawl's cache
    expect(JSON.parse((fetch as unknown as { mock: { calls: [string, RequestInit][] } }).mock.calls[0][1].body as string)).not.toHaveProperty('maxAge');
  });

  it('continues past an unusable provider result through the cascade', async () => {
    const caption = 'Pick ripe tomatoes, salt them, and finish with olive oil.';
    vi.stubGlobal('fetch', firecrawl(null, 500));
    adapters.html.mockResolvedValue('');
    adapters.jina.mockResolvedValue({ content: caption });
    expect(await extractPage(article, 'test-key')).toMatchObject({ text: caption, source: 'jina-reader' });
    expect(adapters.html).toHaveBeenCalledTimes(2);
  });
});
