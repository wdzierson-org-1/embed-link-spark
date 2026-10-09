// @vitest-environment node
import { describe, expect, it, vi } from 'vitest';
import { createWorkerHandler, validateResult } from './handler';

const itemId = '11111111-1111-4111-8111-111111111111';
const jobId = '22222222-2222-4222-8222-222222222222';
const lease = '33333333-3333-4333-8333-333333333333';
const source = 'https://example.org/article';
const job = { id: jobId, kind: 'audit', input: { items: [{ id: itemId, url: source, page_body: 'The source reports nine points.' }] } };
const result = { schema_version: 1, summary: 'One grounded finding.', findings: [{ item_id: itemId, category: 'summary_grounding', severity: 'warning', claim: 'Summary changes points to percent.', evidence: [{ url: source, quote: 'nine points' }], recommendation: 'Preserve source units.' }], proposals: [], uncertainties: [] };
const env = (key: string) => ({ QUALITY_ENABLED: 'true', QUALITY_WORKER_TOKEN: 'a'.repeat(40) }[key]);
const req = (body: unknown, token = 'a'.repeat(40)) => new Request('https://backend.example/quality-worker', { method: 'POST', headers: { authorization: `Bearer ${token}` }, body: JSON.stringify(body) });
const complete = () => ({ action: 'complete', job_id: jobId, lease_token: lease, fence: 2, result: structuredClone(result) });
const observation = { schema_version: 1, item_id: itemId, url: source, captured_at: '2026-10-09T12:00:00Z', outcome: 'retrieved', title: 'Live source', text: 'The current source reports eleven points.', source_truncated: false, image_candidates: [{ url: 'https://example.org/image.jpg', associated: true }], attempts: [{ strategy: 'firecrawl_rendered', outcome: 'retrieved', reason: 'page_read', duration_ms: 123 }], limitations: ['Image pixels are not verified.'] };
const investigation = () => ({ action: 'investigate', job_id: jobId, lease_token: lease, fence: 2 });
function dbFor(reply: any = { ok: true, status: 'completed', idempotent: false }) {
  return { rpc: vi.fn(async (name: string) => ({ data: name === 'hosted_quality_job_context' ? job : reply, error: null })) };
}

describe('hosted quality worker boundary', () => {
  it('rejects missing/wrong credentials before touching the database', async () => {
    const db = dbFor(); const response = await createWorkerHandler({ db, env })(req({ action: 'claim' }, 'wrong'));
    expect(response.status).toBe(401); expect(db.rpc).not.toHaveBeenCalled();
  });
  it('does not claim work unless explicitly enabled', async () => {
    const db = dbFor(); const response = await createWorkerHandler({ db, env: k => k === 'QUALITY_WORKER_TOKEN' ? 'a'.repeat(40) : undefined })(req({ action: 'claim' }));
    expect(await response.json()).toEqual({ job: null, disabled: true }); expect(db.rpc).not.toHaveBeenCalled();
  });
  it('returns a server-selected claim and rejects arbitrary requested scopes', async () => {
    const db = dbFor(job); const handle = createWorkerHandler({ db, env });
    expect((await handle(req({ action: 'claim', user_id: itemId }))).status).toBe(400);
    expect(await (await handle(req({ action: 'claim' }))).json()).toEqual({ job });
    expect(db.rpc).toHaveBeenCalledWith('claim_hosted_quality_job', {});
  });
  it('validates evidence and item scope before completing', async () => {
    const db = dbFor(); const body = complete(); body.result.findings[0].item_id = jobId;
    expect((await createWorkerHandler({ db, env })(req(body))).status).toBe(400);
    expect(db.rpc.mock.calls.map(c => c[0])).toEqual(['hosted_quality_job_context']);
  });
  it('rejects fabricated source quotes, unrelated URLs, arbitrary keys and missing audit item identity', () => {
    for (const mutate of [
      (r: any) => { r.findings[0].evidence[0].quote = 'invented'; },
      (r: any) => { r.findings[0].evidence[0].url = 'https://other.example/article'; },
      (r: any) => { r.findings[0].patch = { title: 'overwrite' }; },
      (r: any) => { delete r.findings[0].item_id; },
    ]) { const r = structuredClone(result); mutate(r); expect(() => validateResult(r, job)).toThrow(); }
  });
  it('accepts exact source evidence without mutating input and rejects unsafe research citations', () => {
    expect(validateResult(result, job)).toEqual(result);
    for (const url of ['http://example.org/a', 'https://127.0.0.1/a', 'https://localhost/a', 'https://user:pass@example.org/a']) {
      const r = structuredClone(result); r.findings[0].evidence[0].url = url;
      expect(() => validateResult(r, { ...job, kind: 'research' })).toThrow();
    }
  });
  it('maps stale fencing to conflict and passes lease unchanged', async () => {
    const db = dbFor({ ok: false, error: 'lease_lost' }); const response = await createWorkerHandler({ db, env })(req(complete()));
    expect(response.status).toBe(409);
    expect(db.rpc).toHaveBeenLastCalledWith('complete_hosted_quality_job', expect.objectContaining({ target_id: jobId, token: lease, expected_fence: 2, result_payload: result }));
  });
  it('returns an idempotent receipt and accepts completion while claiming is disabled', async () => {
    const db = dbFor({ ok: true, status: 'completed', idempotent: true });
    const response = await createWorkerHandler({ db, env: k => k === 'QUALITY_ENABLED' ? 'false' : env(k) })(req(complete()));
    expect(response.status).toBe(200); expect((await response.json()).idempotent).toBe(true);
  });
  it('rejects oversized requests and nonfinite usage without completion writes', async () => {
    const db = dbFor(); const handle = createWorkerHandler({ db, env });
    expect((await handle(req({ action: 'fail', reason: 'x'.repeat(130000) }))).status).toBe(413);
    expect((await handle(req({ ...complete(), usage: { cost_usd: -1 } }))).status).toBe(400);
    expect(db.rpc).not.toHaveBeenCalled();
  });
  it('forwards heartbeat and bounded failures, never allows item mutation actions', async () => {
    const db = dbFor({ ok: true, status: 'queued' }); const handle = createWorkerHandler({ db, env });
    const identity = { job_id: jobId, lease_token: lease, fence: 2 };
    expect((await handle(req({ action: 'heartbeat', ...identity }))).status).toBe(200);
    expect((await handle(req({ action: 'fail', ...identity, reason: 'worker_timeout' }))).status).toBe(200);
    expect((await handle(req({ action: 'patch', ...identity, title: 'bad' }))).status).toBe(400);
  });
  it('gates paid research and rejects requested item or URL overrides before reserving', async () => {
    const db = dbFor(); const collect = vi.fn();
    const handle = createWorkerHandler({ db, env, collect } as any);
    expect((await handle(req(investigation()))).status).toBe(503);
    expect((await handle(req({ ...investigation(), url: source }))).status).toBe(400);
    expect(db.rpc).not.toHaveBeenCalled(); expect(collect).not.toHaveBeenCalled();
  });
  it('uses the server-selected item and persists the immutable observation before returning it', async () => {
    const item = job.input.items[0]; const attempt = '44444444-4444-4444-8444-444444444444';
    const db = { rpc: vi.fn(async (name: string) => ({ data: name === 'reserve_hosted_quality_investigation' ? { ok: true, item, attempt_token: attempt } : { ok: true, observation }, error: null })) };
    const collect = vi.fn(async () => observation);
    const handle = createWorkerHandler({ db, env: (k: string) => ({ QUALITY_RESEARCH_ENABLED: 'true', FIRECRAWL_API_KEY: 'test-provider' }[k] || env(k)), collect } as any);
    const response = await handle(req(investigation()));
    expect(response.status).toBe(200); expect(await response.json()).toEqual({ ok: true, observation });
    expect(collect).toHaveBeenCalledExactlyOnceWith(item, expect.objectContaining({ apiKey: 'test-provider' }));
    expect(db.rpc).toHaveBeenLastCalledWith('finish_hosted_quality_investigation', { target_id: jobId, token: lease, expected_fence: 2, attempt_token: attempt, observation_payload: observation });
  });
  it('returns cached evidence without a provider call and refuses stale, busy or exhausted reservations', async () => {
    for (const reservation of [{ ok: true, cached: true, observation }, { ok: false, error: 'lease_lost' }, { ok: false, error: 'investigation_busy' }, { ok: false, error: 'retrieval_budget_exhausted' }]) {
      const db = dbFor(reservation); const collect = vi.fn();
      const response = await createWorkerHandler({ db, env: (k: string) => ({ QUALITY_RESEARCH_ENABLED: 'true', FIRECRAWL_API_KEY: 'test-provider' }[k] || env(k)), collect } as any)(req(investigation()));
      expect(response.status).toBe(reservation.ok ? 200 : 409); expect(collect).not.toHaveBeenCalled();
      expect(db.rpc).toHaveBeenCalledTimes(1);
    }
  });
  it('does not persist out-of-scope or oversized collector output', async () => {
    for (const bad of [{ ...observation, item_id: jobId }, { ...observation, url: 'https://other.example/' }, { ...observation, text: 'x'.repeat(6001) }]) {
      const db = dbFor({ ok: true, item: job.input.items[0], attempt_token: lease });
      const response = await createWorkerHandler({ db, env: (k: string) => ({ QUALITY_RESEARCH_ENABLED: 'true', FIRECRAWL_API_KEY: 'test-provider' }[k] || env(k)), collect: async () => bad } as any)(req(investigation()));
      expect(response.status).toBe(400); expect(db.rpc).toHaveBeenCalledTimes(1);
    }
  });
  it('persists all three bounded strategy attempts in one leased reservation', async () => {
    const escalated = { ...observation, attempts: [
      { strategy: 'firecrawl_rendered', outcome: 'blocked', reason: 'access_wall', duration_ms: 12_000 },
      { strategy: 'jina_reader', outcome: 'retrieved', reason: 'reader_source', duration_ms: 6_000 },
      { strategy: 'medium_public_feed', outcome: 'retrieved', reason: 'exact_entry_artwork', duration_ms: 5_000 },
    ] };
    const db = { rpc: vi.fn(async (name: string) => ({ data: name === 'reserve_hosted_quality_investigation' ? { ok: true, item: job.input.items[0], attempt_token: lease } : { ok: true, observation: escalated }, error: null })) };
    const collect = vi.fn(async () => escalated);
    const response = await createWorkerHandler({ db, env: (k: string) => ({ QUALITY_RESEARCH_ENABLED: 'true', FIRECRAWL_API_KEY: 'test-provider', JINA_API_KEY: 'test-reader' }[k] || env(k)), collect } as any)(req(investigation()));
    expect(response.status).toBe(200); expect(db.rpc).toHaveBeenCalledTimes(2);
    expect(collect).toHaveBeenCalledExactlyOnceWith(job.input.items[0], expect.objectContaining({ jinaApiKey: 'test-reader' }));
    expect(await response.json()).toEqual({ ok: true, observation: escalated });
  });
  it('rejects excessive or invalid strategy telemetry before persistence', async () => {
    const attempt = { strategy: 'firecrawl_rendered', outcome: 'retrieved', reason: 'rendered_source', duration_ms: 123 };
    for (const attempts of [[], Array(4).fill(attempt), [{ ...attempt, strategy: 'arbitrary_browser' }], [{ ...attempt, outcome: 'fixed' }], [{ ...attempt, duration_ms: 0.5 }]]) {
      const db = dbFor({ ok: true, item: job.input.items[0], attempt_token: lease });
      const response = await createWorkerHandler({ db, env: (k: string) => ({ QUALITY_RESEARCH_ENABLED: 'true', FIRECRAWL_API_KEY: 'test-provider' }[k] || env(k)), collect: async () => ({ ...observation, attempts }) } as any)(req(investigation()));
      expect(response.status).toBe(400); expect(db.rpc).toHaveBeenCalledTimes(1);
    }
  });
  it('persists a collector refusal for the exact unsafe URL without source evidence', async () => {
    const unsafe = { ...job.input.items[0], url: 'https://example.com/?access_token=PRIVATE_CANARY' };
    const refusal = { ...observation, url: unsafe.url, outcome: 'unavailable', title: '', text: '', image_candidates: [], source_truncated: false,
      attempts: [{ strategy: 'firecrawl_rendered', outcome: 'unavailable', reason: 'unsafe_url', duration_ms: 0 }] };
    const db = { rpc: vi.fn(async (name: string) => ({ data: name === 'reserve_hosted_quality_investigation' ? { ok: true, item: unsafe, attempt_token: lease } : { ok: true, observation: refusal }, error: null })) };
    const collect = vi.fn(async () => refusal);
    const response = await createWorkerHandler({ db, env: (k: string) => ({ QUALITY_RESEARCH_ENABLED: 'true', FIRECRAWL_API_KEY: 'test-provider' }[k] || env(k)), collect } as any)(req(investigation()));
    expect(response.status).toBe(200); expect(db.rpc).toHaveBeenCalledTimes(2);
    expect(db.rpc.mock.calls[1][1].observation_payload).toEqual(refusal);
  });
  it('does not let unsafe refusal telemetry carry source text, images or further attempts', async () => {
    const unsafe = { ...job.input.items[0], url: 'https://example.com/?access_token=PRIVATE_CANARY' };
    const refusal = { ...observation, url: unsafe.url, outcome: 'unavailable', title: '', text: '', image_candidates: [], source_truncated: false,
      attempts: [{ strategy: 'firecrawl_rendered', outcome: 'unavailable', reason: 'unsafe_url', duration_ms: 0 }] };
    for (const patch of [{ title: 'secret source' }, { text: 'secret source' }, { image_candidates: observation.image_candidates }, { outcome: 'retrieved' }, { source_truncated: true }, { attempts: [...refusal.attempts, ...refusal.attempts] }, { url: 'https://example.com/?access_token=OTHER' }]) {
      const db = dbFor({ ok: true, item: unsafe, attempt_token: lease });
      const response = await createWorkerHandler({ db, env: (k: string) => ({ QUALITY_RESEARCH_ENABLED: 'true', FIRECRAWL_API_KEY: 'test-provider' }[k] || env(k)), collect: async () => ({ ...refusal, ...patch }) } as any)(req(investigation()));
      expect(response.status).toBe(400); expect(db.rpc).toHaveBeenCalledTimes(1);
    }
  });
  it('accepts live quotes only for the observed item and refuses invented research sources', () => {
    const researchJob = { ...job, kind: 'research', observation };
    const live: any = structuredClone(result); live.findings[0].evidence[0] = { source: 'live', url: source, quote: 'eleven points' };
    expect(validateResult(live, researchJob)).toEqual(live);
    for (const mutate of [
      (r: any) => { r.findings[0].evidence[0].quote = 'nine points'; },
      (r: any) => { r.findings[0].evidence[0].url = 'https://other.example/article'; },
      (r: any) => { delete r.findings[0].item_id; },
      (r: any) => { r.proposals = [{ title: 'Do this', rationale: 'Because', evidence_urls: ['https://foreign.example/'] }]; },
    ]) { const r = structuredClone(live); mutate(r); expect(() => validateResult(r, researchJob)).toThrow(); }
    expect(() => validateResult(live, { ...researchJob, observation: undefined })).toThrow();
    expect(() => validateResult(live, { ...researchJob, observation: { ...observation, outcome: 'mismatch' } })).toThrow();
    expect(() => validateResult(live, job)).toThrow();
  });
});
