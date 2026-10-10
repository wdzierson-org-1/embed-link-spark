// @vitest-environment node
import { describe, expect, it, vi } from 'vitest';
import { creatorEvidence, recoverSocial } from './socialEnrichment';

const tiktokUrl = 'https://www.tiktok.com/@recipe.author/video/123456789012';
const caption = 'Fresh tomatoes, basil and olive oil make a simple summer salad.';
const item = (url = tiktokUrl) => ({ id: 'item-1', type: 'link', url });
const reply = (body: unknown) => new Response(JSON.stringify(body), { status: 200, headers: { 'content-type': 'application/json' } });

describe('social recovery creator evidence', () => {
  it('retains free TikTok oEmbed creator metadata without claiming a transcript', async () => {
    const fetcher = vi.fn(async () => reply({ title: caption, author_name: 'Recipe Author', author_unique_id: 'recipe.author', author_url: 'https://www.tiktok.com/@recipe.author' }));
    const result = await recoverSocial(item(), {}, {}, fetcher as typeof fetch);
    expect(result.text).toBe(caption);
    expect(result.evidence).toMatchObject({ caption: true, author: 'Recipe Author',
      creator: { name: 'Recipe Author', handle: 'recipe.author', url: 'https://www.tiktok.com/@recipe.author', platform: 'tiktok' } });
    expect(result.evidence).not.toHaveProperty('transcript');
    expect(fetcher).toHaveBeenCalledTimes(1);
    expect(String(fetcher.mock.calls[0][0])).toContain('tiktok.com/oembed?');
  });
  it('retains documented Supadata author fields from the existing metadata request', async () => {
    const fetcher = vi.fn(async () => reply({ url: 'https://www.instagram.com/reel/AbCd/', description: caption,
      author: { displayName: 'Recipe Author', username: '@recipe.author', avatarUrl: 'https://cdn.example/avatar.jpg' } }));
    const result = await recoverSocial(item('https://www.instagram.com/reel/AbCd/'), { transcript_done: true }, { apiKey: 'fixture' }, fetcher as typeof fetch);
    expect(result.evidence).toMatchObject({ author: 'Recipe Author', creator: { name: 'Recipe Author', handle: 'recipe.author', platform: 'instagram' } });
    expect(result.evidence.creator).not.toHaveProperty('url');
    expect(result.evidence).not.toHaveProperty('transcript');
    expect(fetcher).toHaveBeenCalledTimes(1);
  });
  it('keeps an explicit handle when the provider has no display name', async () => {
    const fetcher = vi.fn(async () => reply({ description: caption, author: { username: 'recipe.author' } }));
    const result = await recoverSocial(item(), { transcript_done: true }, { apiKey: 'fixture' }, fetcher as typeof fetch);
    expect(result.evidence).toMatchObject({ author: '@recipe.author', creator: { handle: 'recipe.author', platform: 'tiktok' } });
    expect(result.evidence.creator).not.toHaveProperty('name');
  });
  it('does not infer missing creator metadata from source text or URL', async () => {
    const fetcher = vi.fn(async () => reply({ url: tiktokUrl, description: 'Recipe by @guess. ' + caption }));
    const result = await recoverSocial(item(), { transcript_done: true }, { apiKey: 'fixture' }, fetcher as typeof fetch);
    expect(result.evidence).not.toHaveProperty('author');
    expect(result.evidence).not.toHaveProperty('creator');
    expect(fetcher).toHaveBeenCalledTimes(1);
  });
  it('preserves creator evidence while an existing transcript request remains pending', async () => {
    const fetcher = vi.fn(async (input: RequestInfo | URL) => String(input).includes('/metadata?')
      ? reply({ description: caption, author: { displayName: 'Recipe Author' } })
      : new Response(JSON.stringify({ jobId: 'transcript-1' }), { status: 202 }));
    const result = await recoverSocial(item(), {}, { apiKey: 'fixture', now: 0 }, fetcher as typeof fetch);
    expect(result).toMatchObject({ pending: true, evidence: { author: 'Recipe Author', creator: { name: 'Recipe Author', platform: 'tiktok' } },
      state: { transcript: { id: 'transcript-1', polls: 0, started: '1970-01-01T00:00:00.000Z' } } });
    expect(result.evidence).not.toHaveProperty('transcript');
    expect(fetcher).toHaveBeenCalledTimes(2);
  });
  it('preserves creator evidence alongside a usable completed transcript', async () => {
    const transcript = 'This is the spoken account of preparing a tomato salad, starting with the fresh tomatoes.';
    const fetcher = vi.fn(async (input: RequestInfo | URL) => String(input).includes('/metadata?')
      ? reply({ description: caption, author: { displayName: 'Recipe Author' } }) : reply({ content: transcript }));
    const result = await recoverSocial(item(), {}, { apiKey: 'fixture' }, fetcher as typeof fetch);
    expect(result.evidence).toMatchObject({ author: 'Recipe Author', creator: { name: 'Recipe Author', platform: 'tiktok' }, transcript: true });
    expect(result.text).toBe(`${caption}\n\n${transcript}`);
    expect(fetcher).toHaveBeenCalledTimes(2);
  });
});

describe('creator evidence normalization', () => {
  it('does not treat the platform alone or arbitrary field shapes as an identity', () => {
    expect(creatorEvidence('tiktok', {})).toEqual({});
    expect(creatorEvidence('tiktok', { name: { name: 'Guessed' }, handle: 123 })).toEqual({});
    expect(creatorEvidence('other', { name: 'Someone' })).toEqual({});
  });
  it('retains only a supplied URL when the provider omits the display name and handle', () => {
    expect(creatorEvidence('youtube', { url: 'https://www.youtube.com/channel/UC123' })).toEqual({ creator: { url: 'https://www.youtube.com/channel/UC123', platform: 'youtube' } });
  });
  it.each(['http://www.tiktok.com/@author', 'https://www.tiktok.com/@author?token=secret',
    'https://credential@www.tiktok.com/@author', 'https://www.instagram.com/author/', 'https://tiktok.com.evil.example/@author'])
    ('omits unsafe or unrelated author URLs: %s', (url) => {
      expect(creatorEvidence('tiktok', { name: 'Author', url })).toEqual({ author: 'Author', creator: { name: 'Author', platform: 'tiktok' } });
    });
  it('bounds creator strings and rejects handles containing prose or links', () => {
    expect(creatorEvidence('tiktok', { name: 'x'.repeat(201), handle: 'go to https://example.com' })).toEqual({});
    expect(creatorEvidence('tiktok', { name: '  Author  ', handle: '@author' })).toEqual({ author: 'Author', creator: { name: 'Author', handle: 'author', platform: 'tiktok' } });
  });
});
