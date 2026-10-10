import { CRAWLER_UA, fetchHtml, fetchViaJinaReader, fetchViaWayback, htmlToText } from './blockedContentFallbacks.ts';
import { inspectSourceText, sourceIdentity } from './enrichmentQuality.ts';
import { getYouTubeVideoId } from './youtube.ts';
import { parseYouTubeMarkdown } from './youtubeTranscript.ts';

export interface PageCapture {
  text: string;
  kind: 'page' | 'caption' | 'transcript' | 'ocr';
  source: string;
  /** A YouTube video's own facts, read beside its transcript (spec 2026-09-05) */
  youtube?: { description: string | null; durationS: number | null; author: string | null };
}

/**
 * Firecrawl v2: the same `data.markdown` shape as v1, plus the YouTube post-processor, which
 * writes the video's facts, description and transcript into the markdown (watch, live, youtu.be;
 * not Shorts). The language follows `location.languages[0]`.
 */
const scrapeWithFirecrawl = async (url: string, key: string, trace?: string[], options: { fresh?: boolean } = {}): Promise<string | null> => {
  const response = await fetch('https://api.firecrawl.dev/v2/scrape', {
    method: 'POST',
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      url,
      formats: ['markdown'],
      onlyMainContent: true,
      location: { languages: ['en'] },
      // v2 serves a recent scrape from its cache by default; the YouTube post-processor
      // (description + transcript) only runs on a fresh scrape, so a video asks for one
      ...(options.fresh ? { maxAge: 0 } : {}),
    }),
    signal: AbortSignal.timeout(30_000),
  });
  if (!response.ok) {
    const detail = (await response.text().catch(() => '')).slice(0, 200);
    console.warn('firecrawl', response.status, url, detail);
    trace?.push(`firecrawl ${response.status}: ${detail}`);
    return null;
  }
  const payload = await response.json();
  const markdown = payload?.data?.markdown;
  if (typeof markdown !== 'string') {
    trace?.push(`firecrawl 200 without markdown: ${JSON.stringify(payload).slice(0, 200)}`);
    return null;
  }
  trace?.push(`firecrawl 200: ${markdown.length} chars; headings: ${markdown.split('\n').filter((l) => /^#{1,4}\s/.test(l)).slice(0, 8).join(' | ')}`);
  return markdown;
};

/** `trace` (optional) collects what each adapter answered — surfaced by scrape-page-content's extractOnly */
export async function extractPage(url: string, firecrawlKey?: string, trace?: string[]): Promise<PageCapture | null> {
  const accepted = (text: string | null | undefined, source: string): PageCapture | null => {
    const result = inspectSourceText(url, text);
    return result.usable ? { text: result.text.slice(0, 50_000), kind: result.kind, source } : null;
  };

  // A YouTube video's content is its transcript. Firecrawl is the only source that yields one;
  // the cascade below only ever yields YouTube's chrome, so it is never tried for a video
  // (spec 2026-09-05: an honest empty state beats a decorative one).
  const youtubeId = getYouTubeVideoId(url);
  if (youtubeId) {
    if (!firecrawlKey) {
      trace?.push('youtube: no firecrawl key');
      return null;
    }
    try {
      const parsed = parseYouTubeMarkdown(await scrapeWithFirecrawl(url, firecrawlKey, trace, { fresh: true }));
      if (!parsed.transcript) {
        console.warn('youtube transcript unavailable', url);
        trace?.push('youtube: no transcript section');
        return null;
      }
      const checked = inspectSourceText(url, parsed.transcript, 'transcript');
      if (!checked.usable) return null;
      return {
        text: checked.text,
        kind: 'transcript',
        source: 'firecrawl-youtube',
        youtube: { description: parsed.description, durationS: parsed.durationS, author: parsed.author },
      };
    } catch (error) {
      console.warn('firecrawl youtube failed', url, error);
      return null;
    }
  }

  if (firecrawlKey) {
    try {
      const result = accepted(await scrapeWithFirecrawl(url, firecrawlKey, trace), 'firecrawl');
      if (result) return result;
    } catch (error) {
      trace?.push(`firecrawl failed: ${String(error).slice(0, 120)}`);
      /* Try the next approved adapter. */
    }
  }
  for (const [ua, name] of [
    ['Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36', 'direct-fetch'],
    [CRAWLER_UA, 'crawler-ua'],
  ]) {
    const html = await fetchHtml(url, ua, 8_000);
    const result = accepted(html ? htmlToText(html) : null, name);
    if (result) return result;
  }
  const jina = await fetchViaJinaReader(url);
  const reader = accepted(jina?.content, 'jina-reader');
  if (reader) return reader;
  // An archived article can be useful; archived social chrome rarely identifies the saved post.
  if (!['tiktok', 'instagram', 'youtube'].includes(sourceIdentity({ type: 'link', url }).source)) {
    const html = await fetchViaWayback(url);
    const archive = accepted(html ? htmlToText(html) : null, 'wayback-snapshot');
    if (archive) return archive;
  }
  return null;
}
