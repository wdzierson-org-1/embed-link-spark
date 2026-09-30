/** Versioned, deterministic checks. A quality score is evidence coverage, not a factuality guarantee. */
export const QUALITY_VERSION = '2026-09-23.1';
export type ObjectType = 'link' | 'text' | 'image' | 'audio' | 'video' | 'document';
export interface EnrichmentItem {
  id?: string; user_id?: string; type: string; url?: string | null;
  title?: string | null; description?: string | null; summary?: string | null;
  content?: string | null; supplemental_note?: string | null; page_body?: string | null;
  file_path?: string | null; mime_type?: string | null; created_at?: string;
  attributes?: Record<string, any> | null;
}
export interface SourceIdentity { source: string; kind: string; key: string; }
export interface SourceText {
  usable: boolean; text: string; reason?: string; kind: 'page' | 'caption' | 'transcript' | 'ocr';
}
const hostIs = (host: string, domain: string) => host === domain || host.endsWith(`.${domain}`);
export function sourceIdentity(item: EnrichmentItem): SourceIdentity {
  let source = item.type, kind = item.type;
  if (item.type === 'link' && item.url) {
    try {
      const u = new URL(item.url); const host = u.hostname.toLowerCase().replace(/^www\./, '');
      source = host;
      if (hostIs(host, 'tiktok.com')) {
        source = 'tiktok'; kind = /^\/@[^/]+\/?$/.test(u.pathname) ? 'profile' : 'video';
      } else if (hostIs(host, 'instagram.com') || host === 'instagr.am') {
        source = 'instagram'; kind = /^\/(reels?|tv)\//.test(u.pathname) ? 'video' : /^\/p\//.test(u.pathname) ? 'post' : 'profile';
      } else if (hostIs(host, 'youtube.com') || host === 'youtu.be') {
        source = 'youtube'; kind = host === 'youtu.be' || /^\/(watch|shorts\/|live\/|embed\/)/.test(u.pathname) ? 'video' : 'profile';
      } else if (hostIs(host, 'threads.com') || hostIs(host, 'threads.net')) {
        source = 'threads'; kind = 'post';
      } else {
        kind = item.attributes?.link?.flavor || 'page';
      }
    } catch { source = 'invalid-url'; kind = 'unknown'; }
  } else if (item.type === 'image') {
    kind = item.attributes?.media?.kind === 'screenshot' || /^screenshot\b/i.test(item.title || '') ? 'screenshot' : 'photo';
  } else if (item.type === 'document') {
    kind = item.mime_type === 'application/pdf' ? 'pdf' : /officedocument/.test(item.mime_type || '') ? 'office' : 'other';
  }
  return { source, kind, key: `${source}:${kind}` };
}
export function isPlaceholderMetadata(value: string | null | undefined, url?: string | null): boolean {
  const t = (value || '').trim().toLowerCase().replace(/[.!…]+$/, '');
  if (!t) return true;
  if (/^(instagram|login • instagram|log in • instagram|tiktok(?: - make your day)?|youtube|client challenge|just a moment|access denied|403 forbidden|error|found)$/.test(t)) return true;
  if (/^(create an account or log in to instagram|video by .+ on tiktok|tiktok video|link from |saved from )/.test(t)) return true;
  if (/inferred from (?:the )?link|page couldn't be read|unable to access (?:external )?links/.test(t)) return true;
  if (url) {
    if (t === url.toLowerCase()) return true;
    try { const h = new URL(url).hostname.toLowerCase(); if (t === h || t === h.replace(/^www\./, '')) return true; } catch { /* invalid URLs assessed separately */ }
  }
  return false;
}
const plain = (text: string) => text.replace(/!\[([^\]]*)\]\([^)]*\)/g, '$1')
  .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1').replace(/https?:\/\/\S+/g, '')
  .replace(/<[^>]+>/g, ' ').replace(/[*_#`]/g, '').replace(/\s+/g, ' ').trim();

/** Shared gate for EVERY provider, including Firecrawl. Preserve real posts with login chrome. */
export function inspectSourceText(url: string, body: string | null | undefined, kind: SourceText['kind'] = 'page'): SourceText {
  const raw = (body || '').trim(); const text = plain(raw);
  const fail = (reason: string): SourceText => ({ usable: false, text: '', kind, reason });
  if (!text || /^(none|no text|n\/a)$/i.test(text)) return fail('missing_content');
  if (kind === 'transcript' || kind === 'ocr') {
    if (/^(?:no (?:transcript|speech|text)|transcript unavailable|unable to transcribe)/i.test(text)) return fail('missing_content');
    return { usable: true, text: raw, kind };
  }
  const { source, kind: objectKind } = sourceIdentity({ type: 'link', url });
  const start = text.slice(0, 900);
  if (/^(?:.{0,100})?(just a moment|access denied|client challenge|checking your browser|verify you are human)/i.test(start)) return fail('blocked_page');
  if (source === 'tiktok' && /couldn['’]t find this page|video currently unavailable|this video is unavailable/i.test(start)) return fail('unavailable_page');
  if (source === 'instagram' && /sorry,? this page isn['’]t available|the link you followed may be broken/i.test(start)) return fail('unavailable_page');
  if (source === 'youtube' && /skip navigation|sign in to confirm you['’]re not a bot/i.test(start) && !/\btranscript\b.{20}/i.test(text)) return fail('navigation_only');
  if (source === 'instagram') {
    // The plain HTML path exposes a reliable boundary around the actual caption.
    const marker = raw.indexOf('More options');
    if (marker >= 0) {
      const caption = raw.slice(marker + 'More options'.length).split(/Load more comments|Log in to like or comment|More posts from/)[0].trim();
      if (plain(caption).length < 25) return fail('missing_content');
      return { usable: true, text: caption, kind: objectKind === 'profile' ? 'page' : 'caption' };
    }
    if (/create an account or log in to instagram/i.test(text) && text.length < 350) return fail('login_page');
    if (/^(instagram\s*)?(log in|sign up)/i.test(text) && text.length < 120) return fail('login_page');
  }
  if (text.length < 40) return fail('insufficient_content');
  return { usable: true, text: raw, kind: source === 'instagram' && objectKind !== 'profile' ? 'caption' : 'page' };
}
export interface QualityAssessment {
  version: string; source: string; kind: string; source_key: string;
  status: 'ready' | 'partial' | 'blocked' | 'unsupported'; score: number;
  reasons: string[]; content_usable: boolean; card_usable: boolean;
  index_state: 'present' | 'missing' | 'unknown';
  evidence: { text: boolean; transcript: boolean; visual: boolean; ocr: boolean };
}
export function assessEnrichment(item: EnrichmentItem, indexed?: boolean): QualityAssessment {
  const identity = sourceIdentity(item); const reasons: string[] = [];
  const facts = item.attributes?.enrichment?.evidence || {};
  const body = item.page_body?.trim() || '';
  const visualText = typeof facts.visual_text === 'string' ? facts.visual_text.trim() : '';
  const titleUsable = !isPlaceholderMetadata(item.title, item.url) && !/^\d{10,17}\.[a-z0-9]+$/i.test(item.title || '');
  let usable = false, rejected = false, unsupported = false;
  const evidence = { text: false, transcript: false, visual: !!facts.visual, ocr: false };
  if (item.type === 'text') {
    usable = !!item.content?.trim(); evidence.text = usable;
  } else if (item.type === 'image') {
    evidence.ocr = !!body && !/^(none|n\/a)$/i.test(body);
    evidence.visual = !!item.description?.trim() && !isPlaceholderMetadata(item.description);
    usable = evidence.ocr || evidence.visual;
  } else if (item.type === 'audio' || item.type === 'video') {
    evidence.transcript = !!body && inspectSourceText('', body, 'transcript').usable;
    usable = evidence.transcript || (item.type === 'video' && evidence.visual);
  } else if (item.type === 'document') {
    evidence.text = !!body && inspectSourceText('', body, 'ocr').usable;
    usable = evidence.text; unsupported = identity.kind === 'other' && !usable;
  } else if (item.type === 'link') {
    const result = inspectSourceText(item.url || '', body, facts.transcript ? 'transcript' : 'page');
    usable = result.usable || (!!facts.visual && !!visualText); evidence.text = result.usable; evidence.transcript = result.usable && !!facts.transcript;
    rejected = !!body && !result.usable && !usable;
    if (!usable) reasons.push(result.reason || 'missing_content');
    if (identity.source === 'invalid-url') { usable = false; rejected = true; reasons.push('invalid_url'); }
    if (identity.kind === 'video' && !evidence.transcript && !evidence.visual) reasons.push('missing_media_evidence');
    if (identity.source === 'instagram' && identity.kind === 'post' && !evidence.visual) reasons.push('missing_visual_evidence');
  } else unsupported = true;
  if (!usable && !reasons.length) reasons.push(unsupported ? 'unsupported_format' : 'missing_content');
  if (!titleUsable) reasons.push('placeholder_title');
  const descriptionUsable = item.type === 'text' || !isPlaceholderMetadata(item.description, item.url);
  if (!descriptionUsable) reasons.push('placeholder_description');
  if (indexed === false) reasons.push('missing_index');
  if (indexed === undefined) reasons.push('unverified_index');
  const completeEvidence = usable && !reasons.some(r => r === 'missing_media_evidence' || r === 'missing_visual_evidence');
  const card = titleUsable && descriptionUsable;
  return {
    version: QUALITY_VERSION, source: identity.source, kind: identity.kind, source_key: identity.key,
    status: unsupported ? 'unsupported' : rejected ? 'blocked' : completeEvidence && card && indexed === true ? 'ready' : 'partial',
    score: (usable ? 40 : 0) + (completeEvidence ? 20 : 0) + (card ? 20 : 0) + (indexed === true ? 20 : 0),
    reasons: [...new Set(reasons)], content_usable: usable, card_usable: card,
    index_state: indexed === undefined ? 'unknown' : indexed ? 'present' : 'missing', evidence,
  };
}
export interface SourceHealth { assessed: number; ready: number; blocked: number; failures: number; attempts: number; }
export function reviewCadence(health: SourceHealth, previous: 'hourly' | 'daily' = 'daily', healthyStreak = 0) {
  const rate = health.assessed ? health.ready / health.assessed : 1;
  const unhealthy = health.blocked > 0 || (health.assessed > 0 && rate < 0.9) || (health.attempts >= 3 && health.failures / health.attempts >= 0.3);
  const recovered = rate >= 0.95 && health.blocked === 0 && (health.attempts < 3 || health.failures / health.attempts < 0.1);
  const streak = recovered ? healthyStreak + 1 : 0;
  return { cadence: unhealthy || (previous === 'hourly' && streak < 3) ? 'hourly' as const : 'daily' as const, healthyStreak: streak };
}
/** Bounded retries; provider-unavailable never spends hourly paid retries. Version changes reset in SQL. */
export function nextReviewHours(status: QualityAssessment['status'], cadence: 'hourly' | 'daily', attempts: number, unavailable = false): number {
  if (status === 'ready') return 24;
  if (status === 'unsupported' || attempts >= 5) return 168;
  if (unavailable || attempts >= 3 || cadence === 'daily') return 24;
  return Math.max(1, 2 ** Math.max(0, attempts - 1));
}
/** Exclude known contaminated generated fields from rebuilds, while preserving user annotations. */
export function enrichmentSearchText(item: EnrichmentItem): string {
  const quality = assessEnrichment(item);
  const protectedFields = item.attributes?.enrichment?.protected_fields || {};
  const contaminated = quality.status === 'blocked';
  return [(!contaminated || protectedFields.title) && !isPlaceholderMetadata(item.title, item.url) && item.title,
    (!contaminated || protectedFields.description) && !isPlaceholderMetadata(item.description, item.url) && item.description,
    quality.content_usable && item.summary, item.content, item.supplemental_note,
    item.url, quality.content_usable && item.page_body, item.attributes?.media?.file_name,
    quality.evidence.visual && item.attributes?.enrichment?.evidence?.visual_text]
    .filter(Boolean).join('\n\n');
}
