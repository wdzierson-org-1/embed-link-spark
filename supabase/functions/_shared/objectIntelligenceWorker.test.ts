import { describe, expect, it, vi } from 'vitest';
import { runObjectIntelligenceWorker, extractObjectIntelligence } from './objectIntelligenceWorker';
import { buildObjectIntelligenceSource, objectIntelligenceFingerprint, parseObjectIntelligenceOutput } from './objectIntelligence';

const note = () => ({ id: 'item', user_id: 'owner', type: 'text', content: 'Pasta recipe: penne, cherry tomatoes, basil and olive oil. Blister the tomatoes in oil, then toss with cooked penne and basil.', attributes: {} as Record<string, any> });
const output = { interpretation: { kind: 'recipe', summary: 'Pasta with tomatoes and basil.', topics: ['pasta'] }, facts: { recipe: { ingredients: [{ value: 'penne', evidence_ids: ['e1'] }] } }, evidence: [{ id: 'e1', source_id: 'content', quote: 'penne, cherry tomatoes, basil and olive oil' }] };

async function harness(options: { item?: any; attempts?: number; reserve?: boolean; commit?: boolean; index?: boolean; extractError?: boolean; enabled?: boolean } = {}) {
  const item = options.item || note();
  const job = { item_id: item.id, revision: 1, lease_token: 'lease', attempts: options.attempts || 0 };
  const attempts: any[] = [];
  const rpc = vi.fn(async (name: string, args?: any) => {
    if (name === 'begin_object_intelligence_run') return { data: 'run' };
    if (name === 'claim_object_intelligence_jobs') return { data: [job] };
    if (name === 'reserve_object_intelligence_call') return { data: options.reserve !== false };
    if (name === 'commit_object_intelligence') {
      if (options.commit === false) return { data: false };
      item.attributes = { ...item.attributes, object_intelligence: args.intelligence };
    }
    return { data: true };
  });
  const db = { rpc, from: (table: string) => {
    const query = { select: () => query, eq: () => query, maybeSingle: async () => ({ data: item }),
      insert: async (entry: any) => { attempts.push(entry); return { data: null }; } };
    return query;
  } };
  const extract = vi.fn(async (_key: string, source: any, fingerprint: string) => {
    if (options.extractError) throw new Error('provider body with private source text');
    const sourceId = source.sources.find((s: any) => s.text.includes('penne')).id;
    return parseObjectIntelligenceOutput({ ...output, evidence: [{ ...output.evidence[0], source_id: sourceId }] }, source, fingerprint)!;
  });
  const index = vi.fn(async () => ({ success: options.index !== false }));
  const result = await runObjectIntelligenceWorker({ db, config: { enabled: options.enabled !== false, apiKey: 'test', dailyLimit: 200, hourlyLimit: 24 }, extract, index, now: () => 0 });
  return { item, rpc, attempts, extract, index, result };
}

describe('hosted object intelligence pass', () => {
  it('enriches a complete note independently of basic card quality and records the attempt', async () => {
    const h = await harness();
    expect(h.extract).toHaveBeenCalledTimes(1);
    expect(h.item.attributes.object_intelligence.facts.recipe.ingredients[0].value).toBe('penne');
    expect(h.index).toHaveBeenCalledTimes(1);
    expect(h.attempts[0]).toMatchObject({ strategy: 'object-intelligence-v1', outcome: 'improved' });
    expect(h.rpc).toHaveBeenCalledWith('finish_object_intelligence_job', expect.objectContaining({ outcome: 'complete' }));
  });
  it('does not reserve or invoke a model when disabled', async () => {
    const h = await harness({ enabled: false });
    expect(h.rpc).not.toHaveBeenCalled(); expect(h.extract).not.toHaveBeenCalled();
  });
  it('stops after three model failures rather than deferring the exhausted job forever', async () => {
    const h = await harness({ attempts: 3 });
    expect(h.extract).not.toHaveBeenCalled();
    expect(h.rpc).toHaveBeenCalledWith('finish_object_intelligence_job', expect.objectContaining({ outcome: 'failed', failure_code: 'attempts_exhausted' }));
  });
  it('honors the atomic daily/hourly budget before calling the provider', async () => {
    const h = await harness({ reserve: false });
    expect(h.extract).not.toHaveBeenCalled();
    expect(h.rpc).toHaveBeenCalledWith('finish_object_intelligence_job', expect.objectContaining({ outcome: 'deferred' }));
  });
  it('preserves unrelated attributes and honors a user-protected intelligence field', async () => {
    const item = note(); item.attributes = { custom: { retained: true }, enrichment: { protected_fields: { object_intelligence: true } } };
    const h = await harness({ item });
    expect(h.extract).not.toHaveBeenCalled(); expect(h.item.attributes.custom.retained).toBe(true);
    expect(h.rpc).toHaveBeenCalledWith('finish_object_intelligence_job', expect.objectContaining({ outcome: 'protected' }));
  });
  it('does not index a model result rejected by the source compare-and-swap', async () => {
    const h = await harness({ commit: false });
    expect(h.index).not.toHaveBeenCalled();
    expect(h.attempts[0]).toMatchObject({ outcome: 'deferred', reasons: ['item_changed'] });
  });
  it('reuses current intelligence when retrying a failed index, with no second model call', async () => {
    const first = await harness({ index: false });
    expect(first.rpc).toHaveBeenCalledWith('finish_object_intelligence_job', expect.objectContaining({ outcome: 'retry' }));
    const second = await harness({ item: first.item, attempts: 3 });
    expect(second.extract).not.toHaveBeenCalled(); expect(second.index).toHaveBeenCalledTimes(1);
    expect(second.rpc.mock.calls.some(([name]) => name === 'reserve_object_intelligence_call')).toBe(false);
  });
  it('retains the old envelope after a provider failure without leaking provider text to diagnostics', async () => {
    const item = note(); item.attributes.object_intelligence = { old: 'retained' };
    const h = await harness({ item, extractError: true });
    expect(h.item.attributes.object_intelligence).toEqual({ old: 'retained' });
    expect(JSON.stringify(h.attempts)).not.toContain('private source');
    expect(h.rpc).toHaveBeenCalledWith('end_object_intelligence_run', { token: 'run' });
  });
  it('waits for source evidence and does not infer facts from a generated description', async () => {
    const h = await harness({ item: { id: 'i', user_id: 'u', type: 'image', description: 'A leather bag', attributes: {} } });
    expect(h.extract).not.toHaveBeenCalled();
    expect(h.rpc).toHaveBeenCalledWith('finish_object_intelligence_job', expect.objectContaining({ outcome: 'no_evidence' }));
  });
});

describe('object intelligence model boundary', () => {
  it.each(['length', 'content_filter'])('rejects a %s response before persistence', async finish_reason => {
    const source = buildObjectIntelligenceSource(note())!;
    const fetcher = vi.fn(async () => new Response(JSON.stringify({ choices: [{ finish_reason, message: { content: JSON.stringify(output) } }] })));
    await expect(extractObjectIntelligence('test', source, await objectIntelligenceFingerprint(source), fetcher)).rejects.toThrow();
  });
  it('uses constrained JSON output, no tool access, and sends only the source projection', async () => {
    const source = buildObjectIntelligenceSource(note())!;
    const sourceId = source.sources[0].id;
    const fetcher = vi.fn(async () => new Response(JSON.stringify({ choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({ ...output, evidence: [{ ...output.evidence[0], source_id: sourceId }] }) } }] })));
    const result = await extractObjectIntelligence('test', source, await objectIntelligenceFingerprint(source), fetcher);
    expect(result?.facts.recipe).toBeTruthy();
    const body = JSON.parse((fetcher.mock.calls[0] as any)[1].body);
    expect(body.response_format).toMatchObject({ type: 'json_schema', json_schema: { strict: true } });
    expect(body.tools).toBeUndefined(); expect(body.messages[1].content).not.toContain('user_id');
  });
});
