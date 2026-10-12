// @vitest-environment node
import { describe, expect, it, vi } from 'vitest';
import { createVisualHandler } from './handler.ts';

const OWNER = '93ac18ee-2d45-450a-bf60-047a1b8aab96';
const USER = '5b595d5a-c4bd-4a1d-bd55-0c026c7c806b';
const JOB = 'ea1f8c17-d2e4-4c96-8d30-a104e2e68553';
const ITEM = '1c796649-e462-4b86-a585-f28d3d1b8bb2';
const TOKEN = '0151dc78-8316-4089-a6b2-9b00e9e10635';
const URL = 'https://community.openai.com/t/decisions-api-is-now-available-in-public-beta/1403877';
const NOW = Date.parse('2026-10-12T04:00:00Z');
const values: Record<string, string> = {
  CRON_SECRET: 'cron-secret', QUALITY_VISUAL_ENABLED: 'true', QUALITY_CANARY_USER_ID: OWNER,
  QUALITY_CANARY_EMAIL: 'monitor@example.test', QUALITY_CANARY_PASSWORD: 'server-only-password',
  SUPABASE_URL: 'https://exampleproject.supabase.co', SUPABASE_ANON_KEY: 'public-key',
  SUPABASE_SERVICE_ROLE_KEY: 'service-key', OPENAI_API_KEY: 'model-key', QUALITY_SCOPE_USER_IDS: USER,
};
const reference = { id: 'openai-decisions', version: 1, image_path: 'openai-decisions/v1.jpeg', sha256: 'a'.repeat(64), description: 'Two presenters.' };
const claimed = {
  id: JOB, kind: 'canary', owner_id: OWNER, item_id: ITEM, checked_url: URL, fixture_id: reference.id, fixture_version: 1,
  fixture: { id: reference.id, url: URL }, reference, lease_token: TOKEN, fence: 2,
  created_at: new Date(NOW - 5 * 60_000).toISOString(), attempts: 1,
};
const item = { id: ITEM, user_id: OWNER, type: 'link', url: URL, title: 'Decisions API', page_body: 'The original public article.',
  file_path: `${OWNER}/previews/preview_123.jpeg`, attributes: { enrichment: { status: 'complete' } }, is_public: false,
  created_at: new Date(NOW - 5 * 60_000).toISOString() };
const inspection = { schema_version: 1 as const, checked_at: new Date(NOW).toISOString(), checks: [] };
const request = (body: unknown = {}) => new Request('https://backend.example/quality-visual', {
  method: 'POST', headers: { 'x-cron-secret': values.CRON_SECRET }, body: JSON.stringify(body),
});
function setup(options: { env?: Record<string, string | undefined>; job?: any; item?: any; cleanup?: any[] } = {}) {
  const state = { job: options.job === undefined ? structuredClone(claimed) : options.job,
    item: options.item === undefined ? structuredClone(item) : options.item, cleanup: options.cleanup ?? [] };
  const query = { select: vi.fn().mockReturnThis(), eq: vi.fn().mockReturnThis(), maybeSingle: vi.fn(async () => ({ data: state.item, error: null })) };
  const bucket = { download: vi.fn(async () => ({ data: new Blob(['image']), error: null })), remove: vi.fn(async () => ({ data: [], error: null })) };
  const db = {
    rpc: vi.fn(async (name: string) => ({ data:
      name === 'claim_hosted_visual_job' ? state.job : name === 'list_hosted_visual_cleanup' ? state.cleanup :
      name === 'hosted_visual_preview_referenced' ? false : name === 'enqueue_hosted_visual_jobs' ? 1 : true, error: null })),
    from: vi.fn(() => query), storage: { from: vi.fn(() => bucket) },
  };
  const inspect = vi.fn(async (_input, _deps) => inspection);
  const capture = vi.fn(async (_input, deps) => {
    const registered = await deps.recordItem(ITEM);
    return registered ? { status: 'captured' as const, capture_id: JOB, item_id: ITEM, duplicate: false }
      : { status: 'pending' as const, capture_id: JOB, reason: 'registration_failed' as const };
  });
  const auth = { signInWithPassword: vi.fn() };
  const handle = createVisualHandler({ db, auth, env: key => ({ ...values, ...options.env })[key], inspect, capture, now: () => NOW });
  return { handle, state, db, query, bucket, inspect, capture, auth };
}
const fenced = { job_id: JOB, token: TOKEN, expected_fence: 2 };

describe('hosted visual monitor handler', () => {
  it('authenticates cron before all I/O and ignores caller-supplied owner/url', async () => {
    const { handle, db, inspect } = setup();
    expect((await handle(new Request('https://backend.example', { method: 'POST' }))).status).toBe(401);
    expect(db.rpc).not.toHaveBeenCalled();
    expect((await handle(new Request('https://backend.example'))).status).toBe(405);
    await handle(request({ owner_id: USER, url: 'https://evil.example' }));
    expect(inspect.mock.calls[0][0].item.user_id).toBe(OWNER);
    expect(inspect.mock.calls[0][0].item.url).toBe(URL);
  });

  it('prunes while disabled and reports an empty durable queue without paid work', async () => {
    const disabled = setup({ env: { QUALITY_VISUAL_ENABLED: undefined } });
    expect(await (await disabled.handle(request())).json()).toMatchObject({ status: 'disabled' });
    expect(disabled.db.rpc).toHaveBeenCalledWith('prune_hosted_visual_data', {});
    expect(disabled.capture).not.toHaveBeenCalled();
    const idle = setup({ job: null });
    expect(await (await idle.handle(request())).json()).toMatchObject({ status: 'idle' });
    expect(idle.inspect).not.toHaveBeenCalled();
  });

  it('requires configured monitor credentials and rejects invalid report owner IDs', async () => {
    for (const env of [{ QUALITY_CANARY_USER_ID: USER, QUALITY_CANARY_PASSWORD: undefined },
      { QUALITY_REPORT_SCOPE_USER_IDS: 'untrusted-owner' }]) {
      const { handle, db, capture } = setup({ env });
      expect((await handle(request())).status).toBe(503);
      expect(capture).not.toHaveBeenCalled();
      expect(db.rpc.mock.calls.some(([name]) => name === 'claim_hosted_visual_job')).toBe(false);
    }
    const otherOwner = setup({ job: { ...claimed, item_id: null, owner_id: USER } });
    await otherOwner.handle(request());
    expect(otherOwner.capture).not.toHaveBeenCalled();
    expect(otherOwner.db.rpc).toHaveBeenCalledWith('complete_hosted_visual_job', { ...fenced, inspection: null, error_text: 'canary_configuration_mismatch' });
  });

  it('resolves actual card/detail URLs and checks against the registered private reference', async () => {
    const { handle, db, inspect, bucket } = setup();
    expect((await handle(request())).status).toBe(200);
    expect(db.rpc).toHaveBeenCalledWith('enqueue_hosted_visual_jobs', { detail_user_ids: [USER] });
    expect(inspect).toHaveBeenCalledOnce();
    const [input, deps] = inspect.mock.calls[0];
    expect(input.reference).toEqual(reference);
    expect(input.surfaces.map(s => s.surface)).toEqual(['card', 'detail']);
    expect(input.surfaces.every(s => s.source_url.includes(item.file_path))).toBe(true);
    await deps.loadReference(reference.image_path);
    expect(db.storage.from).toHaveBeenCalledWith('quality-reference-images');
    expect(bucket.download).toHaveBeenCalledExactlyOnceWith(reference.image_path);
    expect(await deps.authorizeModel()).toBe(true);
    expect(db.rpc).toHaveBeenCalledWith('authorize_hosted_visual_model', fenced);
    expect(db.rpc).toHaveBeenCalledWith('complete_hosted_visual_job', { ...fenced, inspection, error_text: null });
  });

  it('creates a private capture once and records it before deferring inspection', async () => {
    const { handle, capture, inspect, db } = setup({ job: { ...claimed, item_id: null } });
    expect(await (await handle(request())).json()).toMatchObject({ status: 'captured' });
    expect(capture.mock.calls[0][0]).toMatchObject({ jobId: JOB, expectedUserId: OWNER, fixture: claimed.fixture });
    expect(db.rpc).toHaveBeenCalledWith('register_hosted_visual_capture', { ...fenced, item_id: ITEM });
    expect(inspect).not.toHaveBeenCalled();
    expect(db.rpc.mock.calls.some(([name]) => name === 'complete_hosted_visual_job')).toBe(false);
  });

  it('leaves uncertain requests queued with the original durable job', async () => {
    const { handle, capture, db } = setup({ job: { ...claimed, item_id: null } });
    capture.mockImplementation(async () => ({ status: 'pending', capture_id: JOB, reason: 'request_unconfirmed' } as any));
    expect(await (await handle(request())).json()).toMatchObject({ status: 'deferred' });
    expect(db.rpc).toHaveBeenCalledWith('defer_hosted_visual_job', { ...fenced, reason: 'request_unconfirmed' });
  });

  it('waits for canary enrichment, then records a bounded timeout instead of polling', async () => {
    const pending = { ...item, attributes: { enrichment: { status: 'pending' } } };
    const first = setup({ item: pending });
    expect(await (await first.handle(request())).json()).toMatchObject({ status: 'deferred' });
    expect(first.inspect).not.toHaveBeenCalled();
    expect(first.db.rpc).toHaveBeenCalledWith('defer_hosted_visual_job', { ...fenced, reason: 'enrichment_pending' });
    const expired = setup({ item: { ...pending, created_at: new Date(NOW - 21 * 60_000).toISOString() } });
    await expired.handle(request());
    expect(expired.db.rpc).toHaveBeenCalledWith('complete_hosted_visual_job', { ...fenced, inspection: null, error_text: 'enrichment_settlement_timeout' });
    expect(expired.inspect).not.toHaveBeenCalled();
  });

  it('inspects historical samples immediately and enforces owner identity on fetched rows', async () => {
    const sample = setup({ job: { ...claimed, kind: 'sample', owner_id: USER, reference: null, fixture: null },
      item: { ...item, user_id: USER, is_public: true, file_path: `${USER}/previews/preview_456.jpg`, attributes: {} } });
    await sample.handle(request());
    expect(sample.inspect).toHaveBeenCalledOnce();
    expect(sample.capture).not.toHaveBeenCalled();
    const foreign = setup({ item: { ...item, user_id: USER } });
    await foreign.handle(request());
    expect(foreign.inspect).not.toHaveBeenCalled();
    expect(foreign.db.rpc).toHaveBeenCalledWith('complete_hosted_visual_job', { ...fenced, inspection: null, error_text: 'item_identity_mismatch' });
  });

  it('rejects public canaries and changes to an approved source', async () => {
    for (const changed of [{ is_public: true }, { url: 'https://different.example/page' }]) {
      const { handle, inspect, db } = setup({ item: { ...item, ...changed } });
      await handle(request());
      expect(inspect).not.toHaveBeenCalled();
      expect(db.rpc).toHaveBeenCalledWith('complete_hosted_visual_job', { ...fenced, inspection: null, error_text: 'item_identity_mismatch' });
    }
    const unrelatedReference = setup({ job: { ...claimed, kind: 'sample', fixture: { ...claimed.fixture, url: 'https://unrelated.example' } } });
    await unrelatedReference.handle(request());
    expect(unrelatedReference.inspect).not.toHaveBeenCalled();
    expect(unrelatedReference.db.rpc).toHaveBeenCalledWith('complete_hosted_visual_job', { ...fenced, inspection: null, error_text: 'item_identity_mismatch' });
  });

  it('rejects a changed sample URL even without a baseline, preserving the checked URL provenance', async () => {
    const { handle, inspect, db } = setup({
      job: { ...claimed, kind: 'sample', fixture: null, reference: null },
      item: { ...item, url: 'https://example.org/changed-after-enqueue' },
    });
    await handle(request());
    expect(inspect).not.toHaveBeenCalled();
    expect(db.rpc).toHaveBeenCalledWith('complete_hosted_visual_job', { ...fenced, inspection: null, error_text: 'item_identity_mismatch' });
  });

  it('requires a safe pinned checked URL before processing any claimed job', async () => {
    for (const checked_url of [undefined, 'http://127.0.0.1/private', 'https://user:password@example.org/path',
      'https://example.org/path?access_token=secret', 'https://example.org/path#token=secret']) {
      const { handle, inspect, capture } = setup({ job: { ...claimed, checked_url } });
      expect(await (await handle(request())).json()).toMatchObject({ error: 'invalid_visual_job' });
      expect(inspect).not.toHaveBeenCalled();
      expect(capture).not.toHaveBeenCalled();
    }
  });

  it('does not claim a result was recorded after losing the fenced lease', async () => {
    const { handle, db } = setup();
    db.rpc.mockImplementation(async name => ({ data: name === 'claim_hosted_visual_job' ? claimed : name === 'list_hosted_visual_cleanup' ? [] : name !== 'complete_hosted_visual_job', error: null }));
    expect(await (await handle(request())).json()).toMatchObject({ status: 'superseded' });
  });

  it('cleans only registered monitor items, at most three per wake, even while disabled', async () => {
    const cleanup = Array.from({ length: 5 }, () => ({ job_id: JOB, owner_id: OWNER, item_id: ITEM, file_path: item.file_path, is_public: false, settled: true }));
    const { handle, db, bucket, inspect } = setup({ env: { QUALITY_VISUAL_ENABLED: 'false' }, cleanup });
    expect(await (await handle(request())).json()).toMatchObject({ status: 'disabled' });
    expect(db.rpc.mock.calls.filter(([name]) => name === 'purge_hosted_visual_canary')).toHaveLength(3);
    expect(db.rpc).toHaveBeenCalledWith('purge_hosted_visual_canary', { job_id: JOB, expected_file_path: item.file_path });
    expect(bucket.remove).toHaveBeenCalledWith([item.file_path]);
    expect(db.rpc).toHaveBeenCalledWith('finish_hosted_visual_cleanup', { job_id: JOB, expected_file_path: item.file_path });
    expect(inspect).not.toHaveBeenCalled();
    expect(db.rpc.mock.calls.some(([name]) => name === 'claim_hosted_visual_job')).toBe(false);
  });

  it('leaves approved/reference-linked storage intact during cleanup', async () => {
    const { handle, db, bucket } = setup({ env: { QUALITY_VISUAL_ENABLED: 'false' },
      cleanup: [{ job_id: JOB, owner_id: OWNER, item_id: ITEM, file_path: item.file_path, is_public: false, settled: true }] });
    db.rpc.mockImplementation(async name => ({ data: name === 'list_hosted_visual_cleanup'
      ? [{ job_id: JOB, owner_id: OWNER, item_id: ITEM, file_path: item.file_path, is_public: false, settled: true }] : true, error: null }));
    await handle(request());
    expect(bucket.remove).not.toHaveBeenCalled();
  });

  it('sanitizes exceptions and never exposes credentials or captured text', async () => {
    const { handle, inspect, db } = setup();
    inspect.mockRejectedValue(new Error('model-key private article source'));
    const response = await handle(request());
    expect(await response.json()).toMatchObject({ status: 'failed', reason: 'visual_inspection_failed' });
    expect(db.rpc).toHaveBeenCalledWith('complete_hosted_visual_job', { ...fenced, inspection: null, error_text: 'visual_inspection_failed' });
  });
});
