import { assessEnrichment, inspectSourceText, isPlaceholderMetadata, type EnrichmentItem } from './enrichmentQuality.ts';
export interface RepairCandidate {
  text?: string; title?: string; description?: string; summary?: string;
  evidence?: Record<string, unknown>; strategy: string; pending?: boolean; unavailable?: boolean; reason?: string;
}
/** No model output can rescue a failed source capture. A real caption is useful even without the video. */
export function prepareRepair(item: EnrichmentItem, candidate: RepairCandidate) {
  const quality = assessEnrichment(item);
  const oldFacts = item.attributes?.enrichment?.evidence || {};
  const evidence = { ...candidate.evidence };
  const patch: Record<string, string | null> = {};
  const kind = evidence.transcript || item.type === 'audio' || item.type === 'video' ? 'transcript' : item.type === 'image' || item.type === 'document' ? 'ocr' : 'page';
  const captured = inspectSourceText(item.url || '', candidate.text, kind);
  const current = inspectSourceText(item.url || '', item.page_body, oldFacts.transcript ? 'transcript' : kind);
  if (captured.usable && (!oldFacts.transcript || evidence.transcript)) {
    patch.page_body = captured.text.slice(0, 50_000);
  } else if (quality.status === 'blocked') {
    // Retain the original in enrichment_revisions; never index or summarize the error page.
    patch.page_body = null; patch.summary = null;
    if (isPlaceholderMetadata(item.description, item.url)) patch.description = null;
  } else if (current.usable && current.text !== item.page_body && !oldFacts.transcript) {
    patch.page_body = current.text;
  }
  if (evidence.transcript && !captured.usable) delete evidence.transcript;
  if (evidence.visual && (typeof evidence.visual_text !== 'string' || !evidence.visual_text.trim())) delete evidence.visual;
  const body = Object.hasOwn(patch, 'page_body') ? patch.page_body : quality.content_usable ? item.page_body : null;
  const sourceText = [body, evidence.visual_text || oldFacts.visual_text, item.type === 'image' && candidate.description,
    item.type === 'text' && item.content].filter(Boolean).join('\n\n');
  if (candidate.title && !isPlaceholderMetadata(candidate.title, item.url) && isPlaceholderMetadata(item.title, item.url)) patch.title = candidate.title;
  if (sourceText && candidate.description && !isPlaceholderMetadata(candidate.description, item.url)) patch.description = candidate.description;
  if (sourceText && candidate.summary) patch.summary = candidate.summary;
  return { patch, evidence, sourceText,
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
