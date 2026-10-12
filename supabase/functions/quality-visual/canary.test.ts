// @vitest-environment node
import { describe, expect, it, vi } from 'vitest';
import { captureCanary, cleanupCanary, type CanaryCaptureInput } from './canary.ts';

const OWNER = '93ac18ee-2d45-450a-bf60-047a1b8aab96';
const JOB = 'ea1f8c17-d2e4-4c96-8d30-a104e2e68553';
const ITEM = '1c796649-e462-4b86-a585-f28d3d1b8bb2';
const URL = 'https://community.openai.com/t/decisions-api-is-now-available-in-public-beta/1403877';
const PATH = `${OWNER}/previews/preview_1791579395624.jpeg`;
const jwt = (claims: Record<string, unknown> = {}) =>
  `header.${Buffer.from(JSON.stringify({ sub: OWNER, role: 'authenticated', ...claims })).toString('base64url')}.signature`;
const input: CanaryCaptureInput = {
  jobId: JOB, fixture: { id: 'openai-decisions', url: URL }, expectedUserId: OWNER,
  email: 'monitor@example.test', password: 'secret-password',
  supabaseUrl: 'https://exampleproject.supabase.co', anonKey: 'publishable-test-key',
};
const item = { id: ITEM, user_id: OWNER, url: URL, is_public: false };
const auth = (owner = OWNER, token = jwt()) => ({ signInWithPassword: vi.fn().mockResolvedValue({
  data: { user: { id: owner }, session: { access_token: token, user: { id: owner } } }, error: null,
}) });
const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { 'Content-Type': 'application/json' },
});

describe('private live canary capture', () => {
  it('uses the real capture receipt and private URL pipeline, then registers the returned item', async () => {
    const signIn = auth();
    const fetcher = vi.fn().mockResolvedValue(reply({ item, duplicate: false }));
    const recordItem = vi.fn().mockResolvedValue(true);
    const result = await captureCanary(input, { auth: signIn, fetcher, recordItem });
    expect(result).toEqual({ status: 'captured', capture_id: JOB, item_id: ITEM, duplicate: false });
    expect(signIn.signInWithPassword).toHaveBeenCalledWith({ email: input.email, password: input.password });
    expect(fetcher).toHaveBeenCalledOnce();
    const [url, options] = fetcher.mock.calls[0];
    expect(url).toBe(`${input.supabaseUrl}/functions/v1/capture`);
    expect(options.headers).toMatchObject({ Authorization: `Bearer ${jwt()}`, apikey: input.anonKey });
    expect(options.signal).toBeInstanceOf(AbortSignal);
    expect(JSON.parse(options.body)).toEqual({ capture_id: JOB, kind: 'url', url: URL, is_public: false });
    expect(recordItem).toHaveBeenCalledExactlyOnceWith(ITEM);
  });

  it('reuses the durable job UUID after a lost response and recovers the same item', async () => {
    const fetcher = vi.fn()
      .mockRejectedValueOnce(new Error('response lost'))
      .mockResolvedValueOnce(reply({ item, duplicate: true }));
    const deps = { auth: auth(), fetcher, recordItem: vi.fn().mockResolvedValue(true) };
    expect(await captureCanary(input, deps)).toEqual({ status: 'pending', capture_id: JOB, reason: 'request_unconfirmed' });
    expect(deps.recordItem).not.toHaveBeenCalled();
    expect(await captureCanary(input, deps)).toMatchObject({ status: 'captured', item_id: ITEM, duplicate: true });
    expect(fetcher.mock.calls.map(([, options]) => JSON.parse(options.body).capture_id)).toEqual([JOB, JOB]);
  });

  it('does not capture as a different account or with an OAuth agent token', async () => {
    for (const signIn of [auth('another-user'), auth(OWNER, jwt({ client_id: 'oauth-client' })), auth(OWNER, jwt({ sub: 'another-user' }))]) {
      const fetcher = vi.fn();
      const result = await captureCanary(input, { auth: signIn, fetcher, recordItem: vi.fn() });
      expect(result.status).toBe('failed');
      expect(fetcher).not.toHaveBeenCalled();
    }
  });

  it('rejects malformed durable identities and non-public fixture URLs before signing in', async () => {
    for (const badInput of [
      { ...input, jobId: 'new-job' },
      { ...input, expectedUserId: 'any-user' },
      { ...input, fixture: { ...input.fixture, url: 'http://127.0.0.1/private' } },
      { ...input, fixture: { ...input.fixture, url: 'https://user:password@example.com' } },
    ]) {
      const signIn = auth();
      const result = await captureCanary(badInput, { auth: signIn, fetcher: vi.fn(), recordItem: vi.fn() });
      expect(result).toMatchObject({ status: 'failed', reason: 'invalid_configuration' });
      expect(signIn.signInWithPassword).not.toHaveBeenCalled();
    }
  });

  it('leaves an in-progress capture for the next scheduled wake without polling', async () => {
    const fetcher = vi.fn().mockResolvedValue(reply({ error: 'capture_in_progress' }, 409));
    const result = await captureCanary(input, { auth: auth(), fetcher, recordItem: vi.fn() });
    expect(result).toEqual({ status: 'pending', capture_id: JOB, reason: 'capture_in_progress' });
    expect(fetcher).toHaveBeenCalledOnce();
  });

  it('reports capture refusal without bypassing subscription enforcement or leaking response text', async () => {
    const fetcher = vi.fn().mockResolvedValue(reply({ error: 'subscription_required', message: 'sensitive server error' }, 403));
    const result = await captureCanary(input, { auth: auth(), fetcher, recordItem: vi.fn() });
    expect(result).toEqual({ status: 'failed', capture_id: JOB, reason: 'capture_refused', http_status: 403 });
    expect(JSON.stringify(result)).not.toContain('sensitive');
    expect(fetcher).toHaveBeenCalledOnce();
  });

  it('requires matching private owner/source identity in the actual saved item', async () => {
    for (const changed of [{ user_id: 'other-user' }, { url: 'https://example.com/another' }, { is_public: true }, { id: 'bad-id' }]) {
      const recordItem = vi.fn();
      const result = await captureCanary(input, {
        auth: auth(), fetcher: vi.fn().mockResolvedValue(reply({ item: { ...item, ...changed } })), recordItem,
      });
      expect(result).toMatchObject({ status: 'failed', reason: 'capture_identity_mismatch' });
      expect(recordItem).not.toHaveBeenCalled();
    }
  });

  it('does not report success or delete the item when durable registration fails', async () => {
    for (const recordItem of [vi.fn().mockResolvedValue(false), vi.fn().mockRejectedValue(new Error('registration down'))]) {
      const result = await captureCanary(input, {
        auth: auth(), fetcher: vi.fn().mockResolvedValue(reply({ item })), recordItem,
      });
      expect(result).toEqual({ status: 'pending', capture_id: JOB, reason: 'registration_failed', item_id: ITEM });
    }
  });

  it('bounds a stalled sign-in and never starts a capture afterwards', async () => {
    vi.useFakeTimers();
    try {
      const fetcher = vi.fn();
      const pending = captureCanary(input, {
        auth: { signInWithPassword: () => new Promise(() => {}) }, fetcher, recordItem: vi.fn(),
      });
      await vi.advanceTimersByTimeAsync(15_000);
      expect(await pending).toMatchObject({ status: 'failed', reason: 'authentication_failed' });
      expect(fetcher).not.toHaveBeenCalled();
    } finally { vi.useRealTimers(); }
  });
});

function cleanupDeps(overrides: Record<string, unknown> = {}) {
  return {
    registeredItem: vi.fn().mockResolvedValue({ item_id: ITEM, user_id: OWNER, is_public: false, settled: true, file_path: PATH }),
    deleteItem: vi.fn().mockResolvedValue(true),
    isPreviewReferenced: vi.fn().mockResolvedValue(false),
    removePreview: vi.fn().mockResolvedValue(true),
    ...overrides,
  };
}

describe('registered canary cleanup', () => {
  it('deletes only the settled registered item and its unreferenced owned preview', async () => {
    const deps = cleanupDeps();
    expect(await cleanupCanary({ jobId: JOB, expectedUserId: OWNER }, deps)).toEqual({ deleted: true, preview: 'removed' });
    expect(deps.registeredItem).toHaveBeenCalledExactlyOnceWith(JOB);
    expect(deps.deleteItem).toHaveBeenCalledExactlyOnceWith({ jobId: JOB, itemId: ITEM, userId: OWNER, expectedFilePath: PATH });
    expect(deps.removePreview).toHaveBeenCalledExactlyOnceWith(PATH);
  });

  it('refuses unknown, foreign, public or unsettled records', async () => {
    for (const record of [null,
      { item_id: ITEM, user_id: 'other', is_public: false, settled: true, file_path: PATH },
      { item_id: ITEM, user_id: OWNER, is_public: true, settled: true, file_path: PATH },
      { item_id: ITEM, user_id: OWNER, is_public: false, settled: false, file_path: PATH },
    ]) {
      const deps = cleanupDeps({ registeredItem: vi.fn().mockResolvedValue(record) });
      expect(await cleanupCanary({ jobId: JOB, expectedUserId: OWNER }, deps)).toEqual({ deleted: false, preview: 'kept' });
      expect(deps.deleteItem).not.toHaveBeenCalled();
      expect(deps.removePreview).not.toHaveBeenCalled();
    }
  });

  it('preserves baseline and other referenced assets', async () => {
    const deps = cleanupDeps({ isPreviewReferenced: vi.fn().mockResolvedValue(true) });
    expect(await cleanupCanary({ jobId: JOB, expectedUserId: OWNER }, deps)).toEqual({ deleted: true, preview: 'kept' });
    expect(deps.removePreview).not.toHaveBeenCalled();
  });

  it('never removes external, foreign, traversal or non-preview paths', async () => {
    for (const file_path of ['https://example.com/image.jpg', 'other/previews/preview_123.jpeg',
      `${OWNER}/previews/../baseline.jpeg`, `${OWNER}/previews/%2e%2e/baseline.jpeg`,
      `${OWNER}/baseline.jpeg`, `${OWNER}/previews/approved.jpeg`, null]) {
      const deps = cleanupDeps({ registeredItem: vi.fn().mockResolvedValue({
        item_id: ITEM, user_id: OWNER, is_public: false, settled: true, file_path,
      }) });
      expect(await cleanupCanary({ jobId: JOB, expectedUserId: OWNER }, deps)).toEqual({ deleted: true, preview: 'kept' });
      expect(deps.removePreview).not.toHaveBeenCalled();
    }
  });

  it('keeps the preview when a fenced deletion loses or reference lookup fails', async () => {
    for (const deps of [
      cleanupDeps({ deleteItem: vi.fn().mockResolvedValue(false) }),
      cleanupDeps({ isPreviewReferenced: vi.fn().mockRejectedValue(new Error('database unavailable')) }),
    ]) {
      const result = await cleanupCanary({ jobId: JOB, expectedUserId: OWNER }, deps);
      expect(result.preview).toBe('kept');
      expect(deps.removePreview).not.toHaveBeenCalled();
    }
  });
});
