import { previewImageEvidence } from '../_shared/pagePreview.ts';

type Outcome = 'retrieved' | 'blocked' | 'unavailable' | 'mismatch';
export type LiveEvidence = {
  schema_version: 1;
  item_id: string;
  url: string;
  captured_at: string;
  outcome: Outcome;
  title: string;
  text: string;
  source_truncated: boolean;
  image_candidates: { url: string; associated: boolean }[];
  attempts: { strategy: 'firecrawl_rendered'; outcome: Outcome; reason: string; duration_ms: number }[];
  limitations: string[];
};
const PROVIDER_URL = 'https://api.firecrawl.dev/v2/scrape';
const RESPONSE_LIMIT = 2 * 1024 * 1024;
const TOTAL_TIMEOUT = 23_000;
const object = (value: unknown): value is Record<string, unknown> => value !== null && typeof value === 'object' && !Array.isArray(value);

/** Syntax gate only. All page/browser egress is performed by the fixed hosted provider. */
export function livePublicUrl(value: unknown): value is string {
  if (typeof value !== 'string' || value.length > 2000 || /[\s\\]/.test(value)) return false;
  try {
    const parsed = new URL(value); const host = parsed.hostname.toLowerCase();
    if (parsed.protocol !== 'https:' || parsed.username || parsed.password || (parsed.port && parsed.port !== '443') ||
      !host.includes('.') || host.includes(':') || /^\d+(\.\d+)*$/.test(host) ||
      /(^|\.)(localhost|local|internal|invalid|test|onion|arpa)$/.test(host) || host.endsWith('.')) return false;
    const sensitive = /^(?:access[_-]?token|refresh[_-]?token|id[_-]?token|token|key|api[_-]?key|code|password|pass|secret|signature|sig|session(?:id|_id)?|auth(?:orization)?|jwt|x-amz-.*|x-goog-.*)$/i;
    if ([...parsed.searchParams.keys()].some(key => sensitive.test(key))) return false;
    // Fragments can contain OAuth credentials even though they are not sent in HTTP requests.
    if (sensitive.test(parsed.hash.slice(1).split('=')[0]) || /(?:^|[?&])(?:access_token|token|password|secret|signature)=/i.test(parsed.hash.slice(1))) return false;
    return true;
  } catch { return false; }
}

function sameSource(requested: string, reported: string): boolean {
  if (!livePublicUrl(reported)) return false;
  const a = new URL(requested); const b = new URL(reported);
  const host = (u: URL) => u.hostname.toLowerCase().replace(/^www\./, '');
  const params = (u: URL) => JSON.stringify([...u.searchParams.entries()].sort(([ak, av], [bk, bv]) => ak.localeCompare(bk) || av.localeCompare(bv)));
  // Do not silently collapse product variants, access-specific paths, or query values.
  return host(a) === host(b) && a.pathname === b.pathname && params(a) === params(b);
}

function isAccessWall(title: string, text: string, html: string): boolean {
  if (/^(?:sign[ -]?in|log[ -]?in|login|sign[ -]?up|join linkedin|authwall|just a moment|access denied|security verification|verify (?:you are|you're|your identity)|robot check)(?:\b|\s*[|–-])/i.test(title.trim())) return true;
  const opening = text.slice(0, 1800);
  if (/checking (?:your )?browser before|verify (?:that )?you are human|enable javascript and cookies to continue|you (?:must|need to) (?:sign|log) in to (?:view|read|continue)|(?:sign|log) in to (?:read this|view this|continue reading)|create an account to continue/i.test(opening)) return true;
  if (/create an account to read the full story/i.test(opening) && /(?:this story (?:is|was|available)|made this story available) to (?:Medium )?members only/i.test(opening)) return true;
  if (/manage your professional identity/i.test(opening) && /professional network|million\+? members/i.test(opening)) return true;
  // Match challenge-page markup only when substantive text is absent; normal sites may load CAPTCHA scripts.
  return text.trim().length < 300 && /<title[^>]*>\s*(?:attention required|access denied|just a moment)|id=["']challenge-form["']/i.test(html);
}

class CollectionError extends Error {}
async function readProviderBody(response: Response, signal: AbortSignal): Promise<unknown> {
  if (Number(response.headers.get('content-length') || 0) > RESPONSE_LIMIT) {
    void response.body?.cancel().catch(() => {});
    throw new CollectionError('provider_response_too_large');
  }
  const reader = response.body?.getReader();
  if (!reader) throw new CollectionError('invalid_provider_response');
  const abort = () => { void reader.cancel().catch(() => {}); };
  signal.addEventListener('abort', abort, { once: true });
  const chunks: Uint8Array[] = []; let length = 0;
  try {
    while (true) {
      if (signal.aborted) throw new CollectionError('provider_timeout');
      const { done, value } = await reader.read(); if (done) break;
      length += value.byteLength;
      if (length > RESPONSE_LIMIT) { void reader.cancel().catch(() => {}); throw new CollectionError('provider_response_too_large'); }
      chunks.push(value);
    }
    if (signal.aborted) throw new CollectionError('provider_timeout');
  } finally { signal.removeEventListener('abort', abort); reader.releaseLock(); }
  const bytes = new Uint8Array(length); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  try { return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes)); }
  catch { throw new CollectionError('invalid_provider_response'); }
}

/** One clean public render; no direct source/image fetch, cookies, browser actions, or writes. */
export async function collectLiveEvidence(item: { id: string; url: string }, { apiKey, fetcher = fetch }: { apiKey: string; fetcher?: typeof fetch }): Promise<LiveEvidence> {
  const started = Date.now();
  const safe = livePublicUrl(item.url);
  const base = {
    // Preserve snapshot identity so rejected URLs can receive durable failure telemetry.
    // The backend owns this field; exclude unsafe URLs from model prompts and reports.
    schema_version: 1 as const, item_id: item.id, url: item.url.slice(0, 2000), captured_at: new Date().toISOString(),
    title: '', text: '', source_truncated: false, image_candidates: [],
    limitations: ['public_unauthenticated_render', 'image_pixels_not_verified'],
  };
  const finish = (outcome: Outcome, reason: string, patch: Partial<LiveEvidence> = {}): LiveEvidence => ({
    ...base, outcome, ...patch,
    attempts: [{ strategy: 'firecrawl_rendered', outcome, reason, duration_ms: Math.max(0, Date.now() - started) }],
  });
  if (!safe) return finish('unavailable', 'unsafe_url');
  if (!apiKey?.trim()) return finish('unavailable', 'provider_unconfigured');

  const abort = new AbortController(); let timer: ReturnType<typeof setTimeout> | undefined;
  const deadline = new Promise<never>((_, reject) => { timer = setTimeout(() => { abort.abort(); reject(new CollectionError('provider_timeout')); }, TOTAL_TIMEOUT); });
  try {
    const request = async (): Promise<LiveEvidence> => {
      // Firecrawl v2 options: https://docs.firecrawl.dev/api-reference/endpoint/scrape
      const response = await fetcher(PROVIDER_URL, {
        method: 'POST', redirect: 'error', signal: abort.signal,
        headers: { authorization: `Bearer ${apiKey}`, 'content-type': 'application/json' },
        body: JSON.stringify({ url: item.url, formats: ['markdown', 'rawHtml'], onlyMainContent: true,
          maxAge: 0, waitFor: 1000, timeout: 20000, parsers: [], storeInCache: false, skipTlsVerification: false, proxy: 'auto' }),
      });
      if (!response.ok) {
        void response.body?.cancel().catch(() => {});
        return finish('unavailable', response.status === 429 ? 'provider_rate_limited' : response.status === 401 || response.status === 403 ? 'provider_auth_error' : response.status === 402 ? 'provider_credit_limit' : 'provider_http_error');
      }
      const body = await readProviderBody(response, abort.signal);
      if (!object(body) || body.success !== true || !object(body.data)) throw new CollectionError('invalid_provider_response');
      const data = body.data;
      if ((data.markdown !== undefined && typeof data.markdown !== 'string') || (data.rawHtml !== undefined && typeof data.rawHtml !== 'string') || (data.metadata !== undefined && !object(data.metadata))) throw new CollectionError('invalid_provider_response');
      const metadata = object(data.metadata) ? data.metadata : {};
      if (metadata.title !== undefined && typeof metadata.title !== 'string') throw new CollectionError('invalid_provider_response');
      const title = typeof metadata.title === 'string' ? metadata.title.trim() : '';
      const text = typeof data.markdown === 'string' ? data.markdown.trim() : '';
      const html = typeof data.rawHtml === 'string' ? data.rawHtml : '';
      if (metadata.statusCode === 401 || metadata.statusCode === 403 || metadata.statusCode === 429 || isAccessWall(title, text, html)) return finish('blocked', 'access_wall');
      if (typeof metadata.statusCode === 'number' && metadata.statusCode >= 400) return finish('unavailable', 'source_http_error');
      const reported = [metadata.url, metadata.sourceURL].filter(value => value !== undefined && value !== null && value !== '');
      if (reported.some(value => typeof value !== 'string' || !sameSource(item.url, value))) return finish('mismatch', 'source_identity_mismatch');
      const limitations = [...base.limitations];
      if (typeof metadata.url !== 'string' || !metadata.url) limitations.push('final_url_not_confirmed');
      if (!text) return finish('unavailable', 'empty_source', { limitations });
      const candidates = previewImageEvidence({ url: item.url, html, text, title })
        .filter(candidate => livePublicUrl(candidate.url)).slice(0, 5);
      return finish('retrieved', 'rendered_source', {
        title: title.slice(0, 400), text: text.slice(0, 6000), source_truncated: text.length > 6000,
        image_candidates: candidates, limitations,
      });
    };
    return await Promise.race([request(), deadline]);
  } catch (error) {
    // Provider errors may include tokens or source bodies. Persist only our closed set of codes.
    return finish('unavailable', error instanceof CollectionError ? error.message : abort.signal.aborted ? 'provider_timeout' : 'provider_request_failed');
  } finally { clearTimeout(timer); abort.abort(); }
}
