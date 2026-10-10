import { assessEnrichment, inspectSourceText, isPlaceholderMetadata, type EnrichmentItem } from './enrichmentQuality.ts';
export interface RepairCandidate {
  text?: string; title?: string; description?: string; summary?: string;
  evidence?: Record<string, unknown>; strategy: string; pending?: boolean; unavailable?: boolean; reason?: string;
}
/** extractOnly is a capture contract: preview facts alone never establish a transcript. */
export function pageCaptureCandidate(item: EnrichmentItem, value: unknown): RepairCandidate | null {
  if (!value || typeof value !== 'object') return null;
  const capture = value as Record<string, unknown>;
  const kind = capture.kind;
  if (capture.success !== true || typeof capture.text !== 'string' || typeof capture.source !== 'string' || !capture.source.trim() ||
    (kind !== 'page' && kind !== 'caption' && kind !== 'transcript' && kind !== 'ocr')) return null;
  const checked = inspectSourceText(item.url || '', capture.text, kind);
  if (!checked.usable) return null;
  const evidence: Record<string, unknown> = { capture_kind: kind };
  let description: string | undefined;
  if (kind === 'caption') evidence.caption = true;
  if (kind === 'transcript') {
    evidence.transcript = true; evidence.transcript_source = capture.source;
    const facts = capture.facts && typeof capture.facts === 'object' ? capture.facts as Record<string, unknown> : {};
    if (typeof facts.language === 'string' && facts.language.trim()) evidence.language = facts.language.trim();
    if (typeof facts.author === 'string' && facts.author.trim()) evidence.author = facts.author.trim();
    if (typeof facts.durationS === 'number' && Number.isFinite(facts.durationS) && facts.durationS > 0) evidence.duration_s = facts.durationS;
    if (typeof facts.description === 'string' && !isPlaceholderMetadata(facts.description, item.url) &&
      isPlaceholderMetadata(item.description, item.url)) description = facts.description.trim();
  }
  // Preparation applies the same gate and strips source chrome; preserve its boundaries until then.
  return { strategy: capture.source, text: capture.text, evidence, ...(description ? { description } : {}) };
}
/** No model output can rescue a failed source capture. A real caption is useful even without the video. */
export function prepareRepair(item: EnrichmentItem, candidate: RepairCandidate) {
  const quality = assessEnrichment(item);
  const oldFacts = item.attributes?.enrichment?.evidence || {};
  const evidence = { ...candidate.evidence };
  const patch: Record<string, string | null> = {};
  const kind = evidence.transcript === true || item.type === 'audio' || item.type === 'video' ? 'transcript' : evidence.capture_kind === 'ocr' || item.type === 'image' || item.type === 'document' ? 'ocr' : 'page';
  const captured = inspectSourceText(item.url || '', candidate.text, kind);
  const current = inspectSourceText(item.url || '', item.page_body, oldFacts.transcript ? 'transcript' : kind);
  const acceptsBody = captured.usable && (!oldFacts.transcript || evidence.transcript === true);
  if (acceptsBody) {
    patch.page_body = captured.text.slice(0, 50_000);
  } else if (quality.status === 'blocked') {
    // Retain the original in enrichment_revisions; never index or summarize the error page.
    patch.page_body = null; patch.summary = null;
    if (isPlaceholderMetadata(item.description, item.url)) patch.description = null;
  } else if (current.usable && current.text !== item.page_body && !oldFacts.transcript) {
    patch.page_body = current.text;
  }
  if (!acceptsBody) {
    // Body provenance must never describe a rejected capture or relabel an existing transcript.
    for (const key of ['capture_kind', 'caption', 'transcript', 'transcript_source', 'language', 'duration_s']) delete evidence[key];
    if (candidate.evidence?.capture_kind === 'transcript' && !evidence.creator) delete evidence.author;
  }
  if (evidence.visual && (typeof evidence.visual_text !== 'string' || !evidence.visual_text.trim())) delete evidence.visual;
  const body = Object.hasOwn(patch, 'page_body') ? patch.page_body : quality.content_usable ? item.page_body : null;
  const sourceText = [body, evidence.visual_text || oldFacts.visual_text, item.type === 'image' && candidate.description,
    item.type === 'text' && item.content].filter(Boolean).join('\n\n');
  if (candidate.title && !isPlaceholderMetadata(candidate.title, item.url) && isPlaceholderMetadata(item.title, item.url)) patch.title = candidate.title;
  if (sourceText && candidate.description && !isPlaceholderMetadata(candidate.description, item.url)) patch.description = candidate.description;
  if (sourceText && candidate.summary) patch.summary = candidate.summary;
  const sourceIsTranscript = !!body && (acceptsBody ? evidence.transcript === true : oldFacts.transcript === true);
  return { patch, evidence, sourceText, sourceIsTranscript,
    needsTitle: !!sourceText && isPlaceholderMetadata(item.title, item.url) && !patch.title,
    needsSummary: !!sourceText && (!item.summary || isPlaceholderMetadata(item.description, item.url) || Object.hasOwn(patch, 'page_body') || !!evidence.visual),
  };
}
export function selectRepairAdapter(item: EnrichmentItem): 'social' | 'page' | 'image' | 'transcribe' | 'document' | 'metadata' | 'unsupported' {
  const quality = assessEnrichment(item);
  if (item.type === 'link' && ['tiktok','instagram','youtube'].includes(quality.source) && quality.kind !== 'profile') return 'social';
  if (quality.content_usable) return 'metadata';
  if (item.type === 'link') return 'page';
  if (item.type === 'image') return 'image';
  if (item.type === 'audio' || item.type === 'video') return 'transcribe';
  if (item.type === 'document' && quality.kind !== 'other') return 'document';
  return item.type === 'text' ? 'metadata' : 'unsupported';
}
