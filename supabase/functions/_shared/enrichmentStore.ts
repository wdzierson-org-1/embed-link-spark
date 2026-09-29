import { enrichmentSearchText, type EnrichmentItem, QUALITY_VERSION } from './enrichmentQuality.ts';

export const ENRICHMENT_COLUMNS = 'id,user_id,type,url,title,description,summary,content,supplemental_note,page_body,file_path,mime_type,created_at,attributes';
export function itemSnapshot(item: EnrichmentItem): Record<string, unknown> {
  return Object.fromEntries(['type','url','title','description','summary','content','supplemental_note','page_body','file_path','mime_type','attributes']
    .map(key => [key, (item as Record<string, unknown>)[key] ?? null]));
}
export async function searchFingerprint(item: EnrichmentItem): Promise<string> {
  const bytes = new TextEncoder().encode(`${QUALITY_VERSION}\n${enrichmentSearchText(item)}`);
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))].map(x => x.toString(16).padStart(2, '0')).join('');
}
export function chunkSearchText(text: string): string[] {
  const cleaned = text.trim().replace(/[^\S\n]+/g, ' ').replace(/\n{3,}/g, '\n\n');
  if (!cleaned) return [];
  if (cleaned.length <= 1200) return [cleaned];
  const chunks: string[] = [];
  let current = '';
  const flush = () => { if (current) chunks.push(current); current = ''; };
  for (const paragraph of cleaned.split(/\n\s*\n/)) {
    if (paragraph.length > 1200) {
      flush();
      for (let i = 0; i < paragraph.length; i += 450) {
        const part = paragraph.slice(i, i + 600).trim();
        // Retain short final names/identifiers, which are often exactly what people recall.
        if (part) chunks.push(part);
      }
    } else if (current.length + paragraph.length + 2 <= 1200) {
      current += (current ? '\n\n' : '') + paragraph;
    } else { flush(); current = paragraph; }
  }
  flush(); return chunks;
}

export async function applyCandidate(db: any, item: EnrichmentItem, patch: Record<string, unknown>, strategy: string,
  evidence: Record<string, unknown> = {}, token: string | null = null): Promise<boolean> {
  const { data, error } = await db.rpc('apply_enrichment_patch', {
    target_id: item.id, token, expected: itemSnapshot(item), patch, strategy_name: strategy, evidence_patch: evidence,
  });
  if (error) throw error;
  return data === true;
}
