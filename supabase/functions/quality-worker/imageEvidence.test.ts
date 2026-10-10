// @vitest-environment node
import { afterEach, describe, expect, it, vi } from 'vitest';
import { verifyImageAsset } from './imageEvidence.ts';

const source = 'https://www.linkedin.com/in/example-person/';
const url = 'https://media.licdn.com/dms/image/v2/ABC/profile-displayphoto-shrink_800_800/photo.jpg';
const png = Uint8Array.from(Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAHgAAABQCAYAAADSm7GJAAAAvUlEQVR4Ae3BARGAMADEsO5VoG3CsAs+ek3Oc9+PaI2ojaiNqI2ojaiNqI2ojaiNqI2ojaiNqI2ojaiNqI2ojaiNqI2ojaiNqI2ojaiNqI2ojaiNqI2ojaiNqI2ojaiNqI2ojaiNqI2ojaiNqI2ojaiNqI2ojaiNqI2ojaiNqI2ojaiNqI2ojaiNqI2ojaiNqI2ojaiNqI2ojaiNqI2ojaiNqI2ojaiNqI2ojaiNqI2ojaiNqI2ojaiNqI2o/VmWAqdUkIOMAAAAAElFTkSuQmCC', 'base64'));
const jpeg = Uint8Array.from(Buffer.from('/9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAAeKADAAQAAAABAAAAUAAAAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAAABDUHYzZjwCyBOmACZjs+EJ+/8AAEQgAUAB4AwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/bAEMAAgICAgICAwICAwUDAwMFBgUFBQUGCAYGBgYGCAoICAgICAgKCgoKCgoKCgwMDAwMDA4ODg4ODw8PDw8PDw8PD//bAEMBAgICBAQEBwQEBxALCQsQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEP/dAAQACP/aAAwDAQACEQMRAD8A+M6KKK/qQ/mcKKKKACiiigAooooAKKKKACiiigAooooAKKKKAP/Q+M6KKK/qQ/mcKKKKACiiigAooooAKKKKACiiigAooooAKKKKAP/R+M6KKK/qQ/mcKKKKACiiigAooooAKKKKACiiigAooooAKKKKAP/S+M6KKK/qQ/mcKKKKACiiigAooooAKKKKACiiigAooooAKKKKAP/T+M6KKK/qQ/mcKKKKACiiigAooooAKKKKACiiigAooooAKKKKAP/Z', 'base64'));
const webp = Uint8Array.from(Buffer.from('UklGRloAAABXRUJQVlA4IE4AAAAQBQCdASp4AFAAPpFIoUylpCMiIMgAsBIJaQB2AAAMb3U30bUOcZQD3U30bUOcZP9AAP7upj//q7E+FEEv/1qoVPABsxjoQCgIAAAAAAA=', 'base64'));
const webpLossless = Uint8Array.from(Buffer.from('UklGRiQAAABXRUJQVlA4TBcAAAAvd8ATAAdQrWLUsv9hABLC//1SRP9TVwA=', 'base64'));
const imageResponse = (bytes = jpeg, mime = 'image/jpeg', headers = {}) => new Response(bytes, { headers: { 'content-type': mime, ...headers } });
const verify = (response: Response, target = url) => verifyImageAsset({ url: target, associated: true }, source, { fetcher: vi.fn().mockResolvedValue(response) });
afterEach(() => vi.useRealTimers());

describe('bounded public image asset evidence', () => {
  it.each([[png, 'image/png'], [jpeg, 'image/jpeg'], [webp, 'image/webp'], [webpLossless, 'image/webp']] as const)('records actual raster dimensions, size, hash and provenance (%s)', async (bytes, mime) => {
    const result = await verify(imageResponse(bytes, mime));
    expect(result).toMatchObject({ url, source_url: source, associated: true, strategy: 'public_raster_fetch', outcome: 'usable_asset', reason: 'raster_structure_valid', mime_type: mime, byte_length: bytes.length, width: 120, height: 80 });
    expect(result.sha256).toMatch(/^[a-f0-9]{64}$/); expect(Number.isFinite(Date.parse(result.checked_at))).toBe(true);
    expect(result).not.toHaveProperty('visual_match');
  });
  it.each(['image/svg+xml', 'text/html', ''])('does not classify %s responses as raster assets', async mime => {
    expect(await verify(imageResponse(png, mime))).toMatchObject({ outcome: 'invalid', reason: 'non_raster_response' });
  });
  it('records unsupported image formats without claiming corrupt data', async () => {
    expect(await verify(imageResponse(png, 'image/avif'))).toMatchObject({ outcome: 'unavailable', reason: 'unsupported_raster_format' });
  });
  it('rejects corrupt WebP container lengths', async () => {
    const bytes = webp.slice(); bytes[4] += 1;
    expect(await verify(imageResponse(bytes, 'image/webp'))).toMatchObject({ outcome: 'invalid', reason: 'invalid_raster_structure' });
  });
  it('does not send provider credentials or follow redirects', async () => {
    const fetcher = vi.fn().mockResolvedValue(imageResponse()); await verifyImageAsset({ url, associated: true }, source, { fetcher });
    expect(fetcher).toHaveBeenCalledOnce(); const [target, init] = fetcher.mock.calls[0];
    expect(target).toBe(url); expect(init).toMatchObject({ redirect: 'manual', credentials: 'omit', method: 'GET' });
    expect(JSON.stringify(init.headers)).not.toMatch(/authorization|cookie|apikey/i);
  });
  it.each([
    'http://media.licdn.com/x', 'https://user:secret@media.licdn.com/x', 'https://media.licdn.com:8443/x',
    'https://127.0.0.1/x', 'https://[::1]/x', 'https://169.254.169.254/latest', 'https://media.licdn.com/x?token=secret',
    'https://media.licdn.com/x#access_token=secret', 'https://media.licdn.com/x?X-Amz-Signature=secret',
  ])('refuses unsafe URL before egress: %s', async target => {
    const fetcher = vi.fn(); const result = await verifyImageAsset({ url: target, associated: true }, source, { fetcher });
    expect(fetcher).not.toHaveBeenCalled(); expect(result.outcome).toBe('unavailable'); expect(result.reason).toBe('unsafe_image_url');
  });
  it.each(['https://images.attacker.example/x', 'https://media.licdn.com.attacker.example/x', 'https://localhost.invalid/x'])('does not resolve arbitrary hosts: %s', async target => {
    const fetcher = vi.fn(); const result = await verifyImageAsset({ url: target, associated: true }, source, { fetcher });
    expect(fetcher).not.toHaveBeenCalled(); expect(result.reason).toMatch(/unsupported_image_host|unsafe_image_url/);
  });
  it('does not download an unassociated candidate', async () => {
    const fetcher = vi.fn(); const result = await verifyImageAsset({ url, associated: false }, source, { fetcher });
    expect(fetcher).not.toHaveBeenCalled(); expect(result.reason).toBe('image_not_associated');
  });
  it.each([301, 302, 307, 308])('rejects status %s redirects including private target locations', async status => {
    const result = await verify(new Response(null, { status, headers: { location: 'http://169.254.169.254/latest' } }));
    expect(result).toMatchObject({ outcome: 'unavailable', reason: 'image_redirect_rejected' });
  });
  it('rejects a fetcher that has followed a redirect', async () => {
    const response = imageResponse(); Object.defineProperty(response, 'redirected', { value: true });
    expect(await verify(response)).toMatchObject({ reason: 'image_redirect_rejected' });
  });
  it.each([403, 404, 500])('records failed HTTP status %s as unavailable', async status => {
    expect(await verify(new Response('error', { status }))).toMatchObject({ outcome: 'unavailable', reason: 'image_http_error' });
  });
  it('rejects empty response bytes', async () => {
    expect(await verify(imageResponse(new Uint8Array()))).toMatchObject({ outcome: 'invalid', reason: 'empty_image' });
  });
  it.each([['image/jpeg', '<html>Login</html>'], ['image/png', 'garbage'], ['text/html', '<html>blocked</html>']])('rejects corrupted/nonimage bytes (%s)', async (mime, text) => {
    expect(await verify(imageResponse(new TextEncoder().encode(text), mime))).toMatchObject({ outcome: 'invalid' });
  });
  it('rejects a raster MIME/signature mismatch', async () => {
    expect(await verify(imageResponse(png, 'image/jpeg'))).toMatchObject({ outcome: 'invalid', reason: 'image_mime_mismatch' });
  });
  it.each([png, jpeg])('rejects truncated raster data', async bytes => {
    expect(await verify(imageResponse(bytes.slice(0, bytes.length - 3), bytes === png ? 'image/png' : 'image/jpeg'))).toMatchObject({ outcome: 'invalid', reason: 'invalid_raster_structure' });
  });
  it('does not accept a PNG with a corrupt chunk', async () => {
    const bytes = png.slice(); bytes[50] ^= 1;
    expect(await verify(imageResponse(bytes, 'image/png'))).toMatchObject({ outcome: 'invalid', reason: 'invalid_raster_structure' });
  });
  it('rejects a tiny JPEG tracking pixel', async () => {
    const bytes = jpeg.slice(); const sof = bytes.findIndex((byte, i) => byte === 0xff && bytes[i + 1] === 0xc0);
    bytes[sof + 5] = 0; bytes[sof + 6] = 1; bytes[sof + 7] = 0; bytes[sof + 8] = 1;
    expect(await verify(imageResponse(bytes))).toMatchObject({ outcome: 'invalid', reason: 'image_too_small', width: 1, height: 1 });
  });
  it('rejects implausibly large dimensions', async () => {
    const bytes = jpeg.slice(); const sof = bytes.findIndex((byte, i) => byte === 0xff && bytes[i + 1] === 0xc0);
    bytes[sof + 5] = 255; bytes[sof + 6] = 255;
    expect(await verify(imageResponse(bytes))).toMatchObject({ outcome: 'invalid', reason: 'image_dimensions_excessive' });
  });
  it('bounds bytes declared by the server', async () => {
    const cancel = vi.fn(); const stream = new ReadableStream({ cancel });
    expect(await verify(new Response(stream, { headers: { 'content-type': 'image/jpeg', 'content-length': '5242881' } }))).toMatchObject({ outcome: 'invalid', reason: 'image_too_large' });
    expect(cancel).toHaveBeenCalledOnce();
  });
  it('bounds a chunked response with no content length', async () => {
    const cancel = vi.fn(); let chunks = 0;
    const stream = new ReadableStream({ pull(controller) { chunks++; controller.enqueue(new Uint8Array(1_000_000)); }, cancel });
    expect(await verify(new Response(stream, { headers: { 'content-type': 'image/jpeg' } }))).toMatchObject({ outcome: 'invalid', reason: 'image_too_large' });
    expect(cancel).toHaveBeenCalled(); expect(chunks).toBeLessThanOrEqual(7);
  });
  it('bounds nonresponsive fetch at five seconds', async () => {
    vi.useFakeTimers(); let signal: AbortSignal | undefined;
    const fetcher = vi.fn((_target, init) => { signal = init.signal; return new Promise(() => {}); }) as unknown as typeof fetch;
    const pending = verifyImageAsset({ url, associated: true }, source, { fetcher });
    await vi.advanceTimersByTimeAsync(5001);
    expect(await pending).toMatchObject({ outcome: 'unavailable', reason: 'image_timeout', duration_ms: 5000 }); expect(signal?.aborted).toBe(true);
  });
  it('cancels a stalled response stream within five seconds', async () => {
    vi.useFakeTimers(); const cancel = vi.fn(); const stream = new ReadableStream({ cancel });
    const pending = verify(new Response(stream, { headers: { 'content-type': 'image/jpeg' } }));
    await vi.advanceTimersByTimeAsync(5001);
    expect(await pending).toMatchObject({ reason: 'image_timeout' }); expect(cancel).toHaveBeenCalled();
  });
  it('stores only closed error codes, never provider messages', async () => {
    const fetcher = vi.fn().mockRejectedValue(new Error('secret provider-token payload'));
    const result = await verifyImageAsset({ url, associated: true }, source, { fetcher });
    expect(result.reason).toBe('image_request_failed'); expect(JSON.stringify(result)).not.toMatch(/secret|provider-token|payload/);
  });
});
