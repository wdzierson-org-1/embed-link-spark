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
      youtube: { description: 'A quick salad.', durationS: 150, author: 'Chef' },
    });
    const [calledUrl, init] = (fetch as unknown as { mock: { calls: [string, RequestInit][] } }).mock.calls[0];
    expect(calledUrl).toBe('https://api.firecrawl.dev/v2/scrape');
    expect(JSON.parse(init.body as string)).toMatchObject({ url: youtube, formats: ['markdown'], onlyMainContent: true, location: { languages: ['en'] } });
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

describe('any other page', () => {
  it('takes Firecrawl v2 markdown when it is usable', async () => {
    vi.stubGlobal('fetch', firecrawl('Pick ripe tomatoes, salt them, and finish with olive oil. A longer article follows here.'));
    expect(await extractPage(article, 'test-key')).toMatchObject({ source: 'firecrawl', kind: 'page' });
    expect(adapters.html).not.toHaveBeenCalled();
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
