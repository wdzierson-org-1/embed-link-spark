// @vitest-environment node
import { beforeAll, beforeEach, afterAll, afterEach, describe, expect, it, vi } from 'vitest';
const state = vi.hoisted(() => ({ handler: null as any }));
vi.mock('https://deno.land/std@0.168.0/http/server.ts', () => ({ serve: (handler: any) => { state.handler = handler; } }));
const source = 'https://us1.discourse-cdn.com/openai1/article.jpeg';
const request = (monitor = false) => new Request(`https://project.supabase.co/functions/v1/image-proxy?url=${encodeURIComponent(source)}`,
  { headers: monitor ? { 'X-Stash-Visual-Monitor': '1' } : {} });
beforeAll(async () => {
  vi.stubGlobal('fetch', vi.fn());
  vi.spyOn(console, 'log').mockImplementation(() => {}); vi.spyOn(console, 'error').mockImplementation(() => {});
  await import('./index.ts');
});
beforeEach(() => { vi.clearAllMocks(); vi.mocked(fetch).mockImplementation(async () => new Response('image bytes', { headers: { 'content-type': 'image/jpeg' } })); });
afterEach(() => vi.useRealTimers());
afterAll(() => { vi.unstubAllGlobals(); vi.restoreAllMocks(); });

describe('image proxy monitor mode', () => {
  it('enforces no redirects on the actual upstream request and proves the deployed mode', async () => {
    const response = await state.handler(request(true));
    expect(fetch).toHaveBeenCalledWith(source, expect.objectContaining({ redirect: 'error' }));
    expect(response.status).toBe(200);
    expect(response.headers.get('X-Stash-Visual-Mode')).toBe('no-redirect');
    expect(response.headers.get('Cache-Control')).toBe('no-store');
    expect(response.headers.get('Vary')).toBe('X-Stash-Visual-Monitor');
    expect(await response.text()).toBe('image bytes');
  });
  it('preserves the ordinary browser route and cache lifetime', async () => {
    const response = await state.handler(request());
    const init = vi.mocked(fetch).mock.calls[0][1];
    expect(init?.redirect).toBeUndefined();
    expect(response.status).toBe(200); expect(response.headers.get('Cache-Control')).toBe('public, max-age=86400');
    expect(response.headers.get('X-Stash-Visual-Mode')).toBeNull();
    expect(response.headers.get('Vary')).toBe('X-Stash-Visual-Monitor');
  });
  it('returns failure if the guarded upstream redirect is rejected; it never follows or retries', async () => {
    vi.mocked(fetch).mockImplementation(async (_url, init) => {
      if (init?.redirect === 'error') throw new TypeError('redirect rejected');
      return new Response('internal network response', { headers: { 'content-type': 'image/jpeg' } });
    });
    const response = await state.handler(request(true));
    expect(response.status).toBe(500); expect(fetch).toHaveBeenCalledOnce();
    expect(await response.text()).not.toContain('internal network response');
  });
  it('refuses a noncompliant fetcher that already followed a redirect', async () => {
    const upstream = new Response('image', { headers: { 'content-type': 'image/jpeg' } });
    Object.defineProperty(upstream, 'redirected', { value: true });
    vi.mocked(fetch).mockResolvedValue(upstream);
    const response = await state.handler(request(true));
    expect(response.status).toBe(502);
  });

  it('caps monitor downloads at 5 MiB before reading declared oversized bodies', async () => {
    const cancel = vi.fn();
    vi.mocked(fetch).mockResolvedValue(new Response(new ReadableStream({ cancel }), {
      headers: { 'content-type': 'image/jpeg', 'content-length': '5242881' },
    }));
    const response = await state.handler(request(true));
    expect(response.status).toBe(500); expect(cancel).toHaveBeenCalled();
    expect(response.headers.get('X-Stash-Visual-Mode')).toBeNull();
  });
  it('caps undeclared chunked monitor downloads without returning partial image bytes', async () => {
    const cancel = vi.fn(); let chunks = 0;
    vi.mocked(fetch).mockResolvedValue(new Response(new ReadableStream({
      pull(controller) { chunks++; controller.enqueue(new Uint8Array(1_000_000)); }, cancel,
    }), { headers: { 'content-type': 'image/jpeg' } }));
    const response = await state.handler(request(true));
    expect(response.status).toBe(500); expect(cancel).toHaveBeenCalled(); expect(chunks).toBeLessThanOrEqual(7);
    expect(response.headers.get('X-Stash-Visual-Mode')).toBeNull();
  });
  it('bounds the actual monitor upstream request at five seconds even when fetch ignores abort', async () => {
    vi.useFakeTimers(); let signal: AbortSignal | undefined;
    vi.mocked(fetch).mockImplementation(async (_url, init) => { signal = init?.signal as AbortSignal; return await new Promise(() => {}); });
    const pending = state.handler(request(true));
    await vi.advanceTimersByTimeAsync(5_001);
    const response = await pending; expect(response.status).toBe(500); expect(signal?.aborted).toBe(true);
  });
  it('includes stalled body reads in the same five second monitor deadline', async () => {
    vi.useFakeTimers(); const cancel = vi.fn();
    vi.mocked(fetch).mockResolvedValue(new Response(new ReadableStream({ cancel }), { headers: { 'content-type': 'image/jpeg' } }));
    const pending = state.handler(request(true));
    await vi.advanceTimersByTimeAsync(5_001);
    const response = await pending; expect(response.status).toBe(500); expect(cancel).toHaveBeenCalled();
  });

  it('never forwards the monitor control header or caller credentials to the source host', async () => {
    const req = request(true); req.headers.set('Authorization', 'Bearer caller-secret'); req.headers.set('Cookie', 'private-session');
    await state.handler(req);
    expect(JSON.stringify(vi.mocked(fetch).mock.calls[0][1]?.headers)).not.toMatch(/caller-secret|private-session|X-Stash-Visual-Monitor/);
  });
});
