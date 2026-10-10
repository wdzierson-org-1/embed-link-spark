import { previewImageEvidence } from '../_shared/pagePreview.ts';
import { inspectSourceText } from '../_shared/enrichmentQuality.ts';
import { fetchMediumFeedPreview } from '../_shared/mediumFeedPreview.ts';
import { verifyImageAsset, type ImageCheck } from './imageEvidence.ts';

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
  image_checks?: ImageCheck[];
  attempts: { strategy: 'firecrawl_rendered' | 'jina_reader' | 'medium_public_feed'; outcome: Outcome; reason: string; duration_ms: number }[];
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
  const params = (u: URL, omit: (key: string) => boolean = () => false) => JSON.stringify([...u.searchParams.entries()]
    .filter(([key]) => !omit(key)).sort(([ak, av], [bk, bv]) => ak.localeCompare(bk) || av.localeCompare(bv)));
  const mediumId = (u: URL) => {
    if (host(u) !== 'medium.com' && !host(u).endsWith('.medium.com')) return null;
    return u.pathname.match(/^\/p\/([a-f0-9]{12})\/?$/i)?.[1] ||
      u.pathname.match(/^\/(?:@?[a-z0-9_.-]+\/)?[^/]+-([a-f0-9]{12})\/?$/i)?.[1] || null;
  };
  const youtubeId = (u: URL) => {
    if (!['youtube.com', 'm.youtube.com', 'youtu.be'].includes(host(u))) return null;
    const id = host(u) === 'youtu.be' ? u.pathname.match(/^\/([\w-]{11})\/?$/)?.[1] :
      u.pathname === '/watch' && u.searchParams.getAll('v').length === 1 ? u.searchParams.get('v') :
      u.pathname.match(/^\/(?:shorts|live|embed)\/([\w-]{11})\/?$/)?.[1];
    return id && /^[\w-]{11}$/.test(id) ? id : null;
  };
  const medium = mediumId(a); const video = youtubeId(a);
  // Relax canonical URL shape only for provider-owned, exact object identifiers.
  // Unknown query parameters still have to match, including access and playlist context.
  if (medium && mediumId(b) === medium) {
    const tracking = (key: string) => /^(?:source|ref|utm_.+)$/.test(key);
    return params(a, tracking) === params(b, tracking);
  }
  if (video && youtubeId(b) === video) {
    const tracking = (key: string) => /^(?:v|si|feature|utm_.+)$/.test(key);
    return params(a, tracking) === params(b, tracking);
  }
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

type Step = { outcome: Outcome; reason: string; patch?: Partial<LiveEvidence> };
const httpFailure = (status: number): Step => ({ outcome: 'unavailable', reason: status === 429 ? 'provider_rate_limited' :
  status === 401 || status === 403 ? 'provider_auth_error' : status === 402 ? 'provider_credit_limit' : 'provider_http_error' });

/** At most one render, one reader fallback and one exact-entry public feed check.
 * Page egress is restricted to fixed providers and Medium's public author feed.
 * The first associated image gets a separate, bounded trusted-CDN asset check.
 * No source cookies, browser actions or item writes. */
export async function collectLiveEvidence(item: { id: string; url: string }, { apiKey, jinaApiKey, fetcher = fetch }: {
  apiKey: string; jinaApiKey?: string; fetcher?: typeof fetch;
}): Promise<LiveEvidence> {
  const started = Date.now();
  const base = {
    // Preserve snapshot identity so rejected URLs can receive durable failure telemetry.
    // The backend owns this field; exclude unsafe URLs from model prompts and reports.
    schema_version: 1 as const, item_id: item.id, url: item.url.slice(0, 2000), captured_at: new Date().toISOString(),
    title: '', text: '', source_truncated: false, image_candidates: [], image_checks: [],
    limitations: ['public_unauthenticated_render', 'image_pixels_not_verified', 'image_decode_not_verified'],
  };
  const attempts: LiveEvidence['attempts'] = [];
  const finish = (step: Step): LiveEvidence => ({ ...base, outcome: step.outcome, ...step.patch, attempts });
  if (!livePublicUrl(item.url) || !apiKey?.trim()) {
    const reason = !livePublicUrl(item.url) ? 'unsafe_url' : 'provider_unconfigured';
    attempts.push({ strategy: 'firecrawl_rendered', outcome: 'unavailable', reason, duration_ms: 0 });
    return finish({ outcome: 'unavailable', reason });
  }
  if (['youtube.com', 'www.youtube.com', 'm.youtube.com', 'youtu.be'].includes(new URL(item.url).hostname)) base.limitations.push('video_not_viewed');

  const run = async (strategy: LiveEvidence['attempts'][number]['strategy'], budget: number,
    execute: (signal: AbortSignal) => Promise<Step>): Promise<Step> => {
    const stepStarted = Date.now(); const controller = new AbortController(); let timer: ReturnType<typeof setTimeout> | undefined;
    const remaining = Math.max(0, Math.min(budget, TOTAL_TIMEOUT - (stepStarted - started)));
    let result: Step;
    try {
      if (!remaining) throw new CollectionError('collection_budget_exhausted');
      const deadline = new Promise<never>((_, reject) => { timer = setTimeout(() => {
        controller.abort(); reject(new CollectionError('provider_timeout'));
      }, remaining); });
      result = await Promise.race([execute(controller.signal), deadline]);
    } catch (error) {
      // Provider errors may include tokens or source bodies. Persist only closed codes.
      result = { outcome: 'unavailable', reason: error instanceof CollectionError ? error.message : controller.signal.aborted ? 'provider_timeout' : 'provider_request_failed' };
    } finally { clearTimeout(timer); controller.abort(); }
    attempts.push({ strategy, outcome: result.outcome, reason: result.reason, duration_ms: Math.max(0, Date.now() - stepStarted) });
    return result;
  };
  const assess = (title: string, text: string, html: string, reported: unknown[], finalConfirmed: boolean, reason: string): Step => {
    if (reported.some(value => typeof value !== 'string' || !sameSource(item.url, value))) return { outcome: 'mismatch', reason: 'source_identity_mismatch' };
    if (isAccessWall(title, text, html)) return { outcome: 'blocked', reason: 'access_wall' };
    const limitations = [...base.limitations];
    if (!finalConfirmed) limitations.push('final_url_not_confirmed');
    if (!text) return { outcome: 'unavailable', reason: 'empty_source', patch: { limitations } };
    const quality = inspectSourceText(item.url, text);
    if (!quality.usable) return { outcome: quality.reason === 'blocked_page' || quality.reason === 'login_page' ? 'blocked' : 'unavailable', reason: quality.reason || 'unusable_source', patch: { limitations } };
    const candidates = previewImageEvidence({ url: item.url, html, text: quality.text, title })
      .filter(candidate => livePublicUrl(candidate.url)).slice(0, 5);
    return { outcome: 'retrieved', reason, patch: {
      title: title.slice(0, 400), text: quality.text.slice(0, 6000), source_truncated: quality.text.length > 6000,
      image_candidates: candidates, limitations,
    } };
  };
  // Reserve time for alternate evidence within the same 23-second collection budget.
  let selected = await run('firecrawl_rendered', 12_000, async signal => {
    const response = await fetcher(PROVIDER_URL, {
      method: 'POST', redirect: 'error', signal,
      headers: { authorization: `Bearer ${apiKey}`, 'content-type': 'application/json' },
      body: JSON.stringify({ url: item.url, formats: ['markdown', 'rawHtml'], onlyMainContent: true,
        maxAge: 0, waitFor: 1000, timeout: 11000, parsers: [], storeInCache: false, skipTlsVerification: false, proxy: 'auto' }),
    });
    if (!response.ok) { void response.body?.cancel().catch(() => {}); return httpFailure(response.status); }
    const body = await readProviderBody(response, signal);
    if (!object(body) || body.success !== true || !object(body.data)) throw new CollectionError('invalid_provider_response');
    const data = body.data;
    if ((data.markdown !== undefined && typeof data.markdown !== 'string') || (data.rawHtml !== undefined && typeof data.rawHtml !== 'string') || (data.metadata !== undefined && !object(data.metadata))) throw new CollectionError('invalid_provider_response');
    const metadata = object(data.metadata) ? data.metadata : {};
    if (metadata.title !== undefined && typeof metadata.title !== 'string') throw new CollectionError('invalid_provider_response');
    if ([401, 403, 429].includes(Number(metadata.statusCode))) return { outcome: 'blocked', reason: 'access_wall' };
    if (typeof metadata.statusCode === 'number' && metadata.statusCode >= 400) return { outcome: 'unavailable', reason: 'source_http_error' };
    return assess(typeof metadata.title === 'string' ? metadata.title.trim() : '', typeof data.markdown === 'string' ? data.markdown.trim() : '',
      typeof data.rawHtml === 'string' ? data.rawHtml : '',
      [metadata.url, metadata.sourceURL].filter(value => value !== undefined && value !== null && value !== ''),
      typeof metadata.url === 'string' && !!metadata.url, 'rendered_source');
  });
  if (selected.outcome !== 'retrieved') {
    const reader = await run('jina_reader', 6_000, async signal => {
      // JSON reader output exposes URL identity; no generated image captions or cookies.
      const response = await fetcher(`https://r.jina.ai/${item.url}`, {
        redirect: 'error', signal, headers: { accept: 'application/json', 'x-no-cache': 'true', 'x-timeout': '5',
          ...(jinaApiKey?.trim() ? { authorization: `Bearer ${jinaApiKey}` } : {}) },
      });
      if (!response.ok) { void response.body?.cancel().catch(() => {}); return httpFailure(response.status); }
      const body = await readProviderBody(response, signal);
      if (!object(body) || body.code !== 200 || !object(body.data)) throw new CollectionError('invalid_provider_response');
      const data = body.data;
      if (typeof data.url !== 'string' || typeof data.content !== 'string' || (data.title !== undefined && typeof data.title !== 'string')) throw new CollectionError('invalid_provider_response');
      return assess(typeof data.title === 'string' ? data.title.trim() : '', data.content.trim(), '', [data.url], true, 'reader_source');
    });
    // Retain the stronger diagnostic when a later provider is merely unavailable.
    if (reader.outcome === 'retrieved' || reader.outcome === 'mismatch' || (reader.outcome === 'blocked' && selected.outcome !== 'mismatch')) selected = reader;
  }
  const source = new URL(item.url);
  if (!(selected.patch?.image_candidates?.length) && source.hostname === 'medium.com' && /^\/@[a-z0-9_.-]{1,60}\/[^/]+-[a-f0-9]{12}\/?$/i.test(source.pathname)) {
    const feed = await run('medium_public_feed', 5_000, async signal => {
      // The existing parser enforces matching GUID, entry URL and linked artwork.
      const constrainedFetch: typeof fetch = (target, init = {}) => fetcher(target, { ...init, signal });
      const image = await fetchMediumFeedPreview(item.url, constrainedFetch);
      return image && livePublicUrl(image) ? { outcome: 'retrieved', reason: 'exact_entry_artwork', patch: { image_candidates: [{ url: image, associated: true }] } } :
        { outcome: 'unavailable', reason: 'feed_artwork_unavailable' };
    });
    if (feed.patch?.image_candidates?.length) selected = { ...selected, patch: { ...selected.patch,
      image_candidates: feed.patch.image_candidates, limitations: [...(selected.patch?.limitations || base.limitations), 'public_feed_artwork_only'] } };
  }
  const result = finish(selected);
  const candidate = result.image_candidates.find(image => image.associated);
  // Collection keeps its 23-second budget; an asset check adds at most five
  // seconds, within the supervisor's 35-second investigate deadline.
  if (candidate) result.image_checks = [await verifyImageAsset(candidate, item.url, { fetcher })];
  return result;
}
