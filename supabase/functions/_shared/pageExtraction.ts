import { CRAWLER_UA, fetchHtml, fetchViaJinaReader, fetchViaWayback, htmlToText } from './blockedContentFallbacks.ts';
import { inspectSourceText, sourceIdentity } from './enrichmentQuality.ts';
export async function extractPage(url: string, firecrawlKey?: string) {
  const accepted = (text: string | null | undefined, source: string) => {
    const result = inspectSourceText(url, text);
    return result.usable ? { text: result.text.slice(0, 50_000), kind: result.kind, source } : null;
  };
  if (firecrawlKey) {
    try {
      const response = await fetch('https://api.firecrawl.dev/v1/scrape', {
        method: 'POST', headers: { Authorization: `Bearer ${firecrawlKey}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ url, formats: ['markdown'], onlyMainContent: true }), signal: AbortSignal.timeout(15_000),
      });
      if (response.ok) {
        const result = accepted((await response.json())?.data?.markdown, 'firecrawl');
        if (result) return result;
      }
    } catch { /* Try the next approved adapter. */ }
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
