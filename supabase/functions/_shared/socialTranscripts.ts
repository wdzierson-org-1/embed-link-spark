/**
 * Transcripts for short-form video links at save time (Will, 2026-10-10; docs/ui-changes.md):
 * TikTok through SearchApi's `tiktok_transcripts` engine (`TIKTOK_SCRAPE_API_KEY`) and
 * Instagram Reels/video posts through TranscriptFetch (`REELS_SCRAPE_API_KEY`). Both answer
 * inline for short media; neither is polled here (a 202 from TranscriptFetch is left for the
 * maintenance loop). A missing transcript is null, never an error page.
 */
export interface SocialTranscript {
  text: string;
  language?: string;
  /** The post's own text when the provider returns it (Instagram's caption as `title`) */
  description?: string;
  durationS?: number;
  author?: string;
}

const MAX_CHARS = 200_000;

const joinSegments = (segments: unknown): string =>
  Array.isArray(segments)
    ? segments
        .map((segment) => (segment && typeof segment === 'object' && typeof (segment as { text?: unknown }).text === 'string' ? (segment as { text: string }).text.trim() : ''))
        .filter(Boolean)
        .join('\n')
    : '';

const clean = (text: string): string | null => {
  const trimmed = text.replace(/\r\n/g, '\n').trim().slice(0, MAX_CHARS);
  return trimmed.length > 0 ? trimmed : null;
};

/** SearchApi: GET /api/v1/search?engine=tiktok_transcripts&url=… (short links accepted) */
export const fetchTikTokTranscript = async (url: string, key: string, fetcher: typeof fetch = fetch, trace?: string[]): Promise<SocialTranscript | null> => {
  const endpoint = new URL('https://www.searchapi.io/api/v1/search');
  endpoint.searchParams.set('engine', 'tiktok_transcripts');
  endpoint.searchParams.set('url', url);
  const response = await fetcher(endpoint.toString(), {
    headers: { Authorization: `Bearer ${key}`, Accept: 'application/json' },
    signal: AbortSignal.timeout(25_000),
  });
  if (!response.ok) {
    const detail = (await response.text().catch(() => '')).slice(0, 200);
    console.warn('searchapi tiktok', response.status, url, detail);
    trace?.push(`searchapi ${response.status}: ${detail}`);
    return null;
  }
  const payload = (await response.json()) as {
    transcripts?: Array<{ text?: string }>;
    available_languages?: Array<{ lang?: string; is_selected?: boolean }>;
    error?: string;
  };
  if (payload.error) {
    trace?.push(`searchapi error: ${String(payload.error).slice(0, 160)}`);
    return null;
  }
  const text = clean(joinSegments(payload.transcripts));
  trace?.push(text ? `searchapi: ${payload.transcripts?.length ?? 0} segments, ${text.length} chars` : 'searchapi: no transcript');
  if (!text) return null;
  const selected = payload.available_languages?.find((entry) => entry.is_selected)?.lang ?? payload.available_languages?.[0]?.lang;
  return { text, language: selected || undefined };
};

/** TranscriptFetch: POST /api/v2/transcripts/video, held open up to 45 s; 202 means a job we don't wait for */
export const fetchInstagramTranscript = async (url: string, key: string, fetcher: typeof fetch = fetch, trace?: string[]): Promise<SocialTranscript | null> => {
  const response = await fetcher('https://transcriptfetch.com/api/v2/transcripts/video', {
    method: 'POST',
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify({ video: url, timestamps: false, mode: 'auto' }),
    signal: AbortSignal.timeout(55_000),
  });
  if (response.status === 202) {
    trace?.push('transcriptfetch 202: transcription still running (job not awaited)');
    return null;
  }
  if (!response.ok) {
    const detail = (await response.text().catch(() => '')).slice(0, 200);
    console.warn('transcriptfetch', response.status, url, detail);
    trace?.push(`transcriptfetch ${response.status}: ${detail}`);
    return null;
  }
  const payload = (await response.json()) as {
    ok?: boolean;
    data?: { text?: string; segments?: unknown; language?: string; title?: string; duration?: number; channel?: string | null };
    error?: { code?: string; message?: string } | string;
  };
  if (!payload.ok || !payload.data) {
    trace?.push(`transcriptfetch: ${JSON.stringify(payload.error ?? payload).slice(0, 160)}`);
    return null;
  }
  const data = payload.data;
  const text = clean(typeof data.text === 'string' ? data.text : joinSegments(data.segments));
  trace?.push(text ? `transcriptfetch: ${text.length} chars (${data.language ?? '?'})` : 'transcriptfetch: no transcript');
  if (!text) return null;
  return {
    text,
    language: data.language || undefined,
    description: typeof data.title === 'string' && data.title.trim() ? data.title.replace(/\s+/g, ' ').trim().slice(0, 300) : undefined,
    durationS: typeof data.duration === 'number' && Number.isFinite(data.duration) ? Math.round(data.duration) : undefined,
    author: typeof data.channel === 'string' && data.channel.trim() ? data.channel.trim() : undefined,
  };
};
