import { enrichmentSearchText, type EnrichmentItem } from './enrichmentQuality.ts';
import { chunkSearchText, itemSnapshot, searchFingerprint } from './enrichmentStore.ts';

/** Generate first, then compare-and-swap atomically. A failed provider never erases the old index. */
export async function rebuildItemIndex(db: any, item: EnrichmentItem, apiKey: string, fetcher = fetch) {
  const chunks = chunkSearchText(enrichmentSearchText(item));
  if (chunks.length > 500) throw new Error('Enrichment index exceeds chunk budget');
  const rows: Array<{ text: string; embedding: number[] }> = [];
  for (let start = 0; start < chunks.length; start += 100) {
    const batch = chunks.slice(start, start + 100);
    const response = await fetcher('https://api.openai.com/v1/embeddings', {
      method: 'POST', headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ model: 'text-embedding-3-small', input: batch }), signal: AbortSignal.timeout(25_000),
    });
    if (!response.ok) throw new Error(`Embedding provider HTTP ${response.status}`);
    const data = await response.json();
    if (!Array.isArray(data.data) || data.data.length !== batch.length) throw new Error('Incomplete embedding response');
    const ordered = [...data.data].sort((a, b) => a.index - b.index);
    for (let i = 0; i < batch.length; i++) {
      const entry = ordered[i];
      if (entry.index !== i || !Array.isArray(entry.embedding) || entry.embedding.length !== 1536 || !entry.embedding.every(Number.isFinite)) {
        throw new Error('Invalid embedding response');
      }
      rows.push({ text: batch[i], embedding: entry.embedding });
    }
  }
  const { data, error } = await db.rpc('replace_item_embeddings', {
    target_id: item.id, expected: itemSnapshot(item), chunks: rows, fingerprint: await searchFingerprint(item),
  });
  if (error) throw error;
  return { success: data === true, chunksProcessed: data ? rows.length : 0, reason: data ? undefined : 'item_changed' };
}
