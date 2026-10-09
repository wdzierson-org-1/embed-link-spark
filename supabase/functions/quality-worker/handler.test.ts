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
});
