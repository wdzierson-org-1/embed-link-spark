import { describe, expect, it, vi } from 'vitest';
import { recoverCapturedPreview } from './capturedPreview.ts';
const url = 'https://www.linkedin.com/in/scottjenson/';
const image = 'https://media.licdn.com/dms/image/v2/person/profile-displayphoto-shrink_200_200/photo.jpg';
const item = { id: 'item-id', user_id: 'owner-id', type: 'link', url, title: 'Scott Jenson', file_path: null };
const text = `# Scott Jenson\n![Image 1](https://static.licdn.com/aero-v1/sc/logo)\n![Image 2: Scott Jenson](${image})`;
const raster = () => { const bytes = new Uint8Array(150); bytes.set([0xff, 0xd8, 0xff]); return bytes; };
const setup = () => {
  const upload = vi.fn().mockResolvedValue({ error: null });
  const db = { storage: { from: vi.fn().mockReturnValue({ upload }) } };
  const fetcher = vi.fn().mockResolvedValue(new Response(raster(), { headers: { 'Content-Type': 'image/jpeg' } }));
  return { db, upload, fetcher };
};
describe('captured LinkedIn profile image recovery', () => {
  it('copies only the associated portrait to its owner storage', async () => {
    const { db, upload, fetcher } = setup();
    const result = await recoverCapturedPreview(db, item, text, fetcher);
    expect(result?.path).toMatch(/^owner-id\/previews\/item-id-[a-f0-9-]+\.jpg$/);
    expect(fetcher).toHaveBeenCalledWith(image, expect.objectContaining({ redirect: 'error', signal: expect.any(AbortSignal) }));
    expect(db.storage.from).toHaveBeenCalledWith('stash-media');
    expect(upload).toHaveBeenCalledWith(result!.path, expect.any(Uint8Array), expect.objectContaining({ contentType: 'image/jpeg', upsert: false }));
  });
  it('preserves an existing preview without fetching or uploading', async () => {
    const { db, upload, fetcher } = setup();
    expect(await recoverCapturedPreview(db, { ...item, file_path: 'existing.jpg' }, text, fetcher)).toBeNull();
    expect(fetcher).not.toHaveBeenCalled(); expect(upload).not.toHaveBeenCalled();
  });
  it('respects a deliberately cleared and protected preview without an unused upload', async () => {
    const { db, upload, fetcher } = setup();
    const protectedItem = { ...item, attributes: { enrichment: { protected_fields: { file_path: true } } } };
    expect(await recoverCapturedPreview(db, protectedItem, text, fetcher)).toBeNull();
    expect(fetcher).not.toHaveBeenCalled(); expect(upload).not.toHaveBeenCalled();
  });
  it.each([
    image.replace('media.licdn.com', 'media.licdn.com.evil.example'),
    image.replace('media.licdn.com', '127.0.0.1'),
    image.replace('profile-displayphoto', 'article-cover'),
  ])('does not fetch a non-profile/unsupported candidate: %s', async candidate => {
    const { db, fetcher } = setup();
    expect(await recoverCapturedPreview(db, item, `# Scott Jenson\n![Scott Jenson](${candidate})`, fetcher)).toBeNull();
    expect(fetcher).not.toHaveBeenCalled();
  });
  it('does not choose another person or a Medium byline', async () => {
    const { db, fetcher } = setup();
    expect(await recoverCapturedPreview(db, item, `# Scott Jenson\n![Jane Smith](${image})`, fetcher)).toBeNull();
    expect(await recoverCapturedPreview(db, { ...item, url: 'https://medium.com/@writer/story' }, text, fetcher)).toBeNull();
    expect(fetcher).not.toHaveBeenCalled();
  });
  it.each([
    () => new Response('<html>denied</html>', { headers: { 'Content-Type': 'image/jpeg' } }),
    () => new Response(raster(), { headers: { 'Content-Type': 'image/svg+xml' } }),
    () => new Response(raster(), { status: 302, headers: { Location: 'https://127.0.0.1/private' } }),
    () => new Response(raster(), { headers: { 'Content-Type': 'image/jpeg', 'Content-Length': '6000000' } }),
    () => new Response(new Uint8Array(5000001), { headers: { 'Content-Type': 'image/jpeg' } }),
  ])('rejects non-raster, redirects, or oversized responses before storage', async response => {
    const { db, upload, fetcher } = setup(); fetcher.mockResolvedValue(response());
    expect(await recoverCapturedPreview(db, item, text, fetcher)).toBeNull();
    expect(upload).not.toHaveBeenCalled();
  });
  it('returns no patch after a storage error', async () => {
    const { db, upload, fetcher } = setup(); upload.mockResolvedValue({ error: new Error('unavailable') });
    expect(await recoverCapturedPreview(db, item, text, fetcher)).toBeNull();
  });
});
