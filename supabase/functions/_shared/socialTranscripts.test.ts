import { describe, expect, it, vi } from 'vitest';
import { fetchInstagramTranscript, fetchTikTokTranscript } from './socialTranscripts';

const reply = (body: unknown, status = 200) => vi.fn().mockResolvedValue(new Response(JSON.stringify(body), { status }));

describe('TikTok through SearchApi', () => {
  it('asks the tiktok_transcripts engine for the URL and joins the segments', async () => {
    const fetcher = reply({
      transcripts: [{ text: 'Alright, I gotta go in for a pit stop real quick.', start: 0.02 }, { text: 'Okay? Be right back.', start: 5.5 }],
      available_languages: [{ name: 'English', lang: 'en', is_selected: true }],
    });
    const trace: string[] = [];
    const result = await fetchTikTokTranscript('https://vm.tiktok.com/ZMabc123/', 'tk-key', fetcher as unknown as typeof fetch, trace);
    expect(result).toEqual({ text: 'Alright, I gotta go in for a pit stop real quick.\nOkay? Be right back.', language: 'en' });
    const [url, init] = fetcher.mock.calls[0];
    expect(String(url)).toBe('https://www.searchapi.io/api/v1/search?engine=tiktok_transcripts&url=https%3A%2F%2Fvm.tiktok.com%2FZMabc123%2F');
    expect((init as RequestInit).headers).toMatchObject({ Authorization: 'Bearer tk-key' });
    expect(trace[0]).toContain('2 segments');
  });

  it('answers null for an empty transcript, a provider error, or a failed request', async () => {
    expect(await fetchTikTokTranscript('https://www.tiktok.com/@a/video/1', 'k', reply({ transcripts: [] }) as unknown as typeof fetch)).toBeNull();
    expect(await fetchTikTokTranscript('https://www.tiktok.com/@a/video/1', 'k', reply({ error: 'Video not found' }) as unknown as typeof fetch)).toBeNull();
    expect(await fetchTikTokTranscript('https://www.tiktok.com/@a/video/1', 'k', reply({ error: 'Unauthorized' }, 401) as unknown as typeof fetch)).toBeNull();
  });
});

describe('Instagram through TranscriptFetch', () => {
  it('posts the reel and reads the joined text, language, caption and length', async () => {
    const fetcher = reply({
      ok: true,
      data: { kind: 'transcript', text: 'This asteroid might get interesting.', language: 'en', title: 'What happens when we detect an asteroid?', duration: 38.6, channel: null, source: 'audio' },
    });
    const result = await fetchInstagramTranscript('https://www.instagram.com/reel/Dd1gQBsCWE8/', 'rf-key', fetcher as unknown as typeof fetch);
    expect(result).toEqual({ text: 'This asteroid might get interesting.', language: 'en', description: 'What happens when we detect an asteroid?', durationS: 39, author: undefined });
    const [url, init] = fetcher.mock.calls[0];
    expect(String(url)).toBe('https://transcriptfetch.com/api/v2/transcripts/video');
    expect(JSON.parse((init as RequestInit).body as string)).toEqual({ video: 'https://www.instagram.com/reel/Dd1gQBsCWE8/', timestamps: false, mode: 'auto' });
    expect((init as RequestInit).headers).toMatchObject({ Authorization: 'Bearer rf-key' });
  });

  it('joins segments when the provider sends them instead of text', async () => {
    const fetcher = reply({ ok: true, data: { segments: [{ text: 'one' }, { text: 'two' }], language: 'es' } });
    expect(await fetchInstagramTranscript('https://www.instagram.com/reel/x/', 'k', fetcher as unknown as typeof fetch)).toMatchObject({ text: 'one\ntwo', language: 'es' });
  });

  it('does not wait for a long transcription (202), and answers null on errors', async () => {
    const trace: string[] = [];
    expect(await fetchInstagramTranscript('https://www.instagram.com/reel/x/', 'k', reply({ ok: true, job_id: 'j' }, 202) as unknown as typeof fetch, trace)).toBeNull();
    expect(trace[0]).toContain('202');
    expect(await fetchInstagramTranscript('https://www.instagram.com/p/photo/', 'k', reply({ ok: false, error: { code: 'no_media' } }, 422) as unknown as typeof fetch)).toBeNull();
    expect(await fetchInstagramTranscript('https://www.instagram.com/reel/x/', 'k', reply({ ok: false, error: 'nope' }) as unknown as typeof fetch)).toBeNull();
  });
});
