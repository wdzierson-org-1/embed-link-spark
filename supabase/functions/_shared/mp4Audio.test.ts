// @vitest-environment node
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import {
  buildChunkFile,
  memoryReader,
  parseAudioTrack,
  planChunks,
  type ByteReader,
} from './mp4Audio';

const fixture = (name: string): Uint8Array =>
  new Uint8Array(readFileSync(new URL(`./fixtures/${name}`, import.meta.url)));

const MOOV_FIRST = fixture('speech-moov-first.m4a');
const MOOV_LAST = fixture('speech-moov-last.m4a');
const WITH_VIDEO = fixture('speech-with-video.mp4');

// 12.4 s of speech, 1024-frame AAC packets at 22.05 kHz → 270 packets
const EXPECTED_SAMPLES = 270;
const EXPECTED_TIMESCALE = 22050;

const recordingReader = (bytes: Uint8Array) => {
  const spans: Array<[number, number]> = [];
  const inner = memoryReader(bytes);
  const read: ByteReader = (start, end) => {
    spans.push([start, end]);
    return inner(start, end);
  };
  return { read, spans };
};

const concatSamples = (
  bytes: Uint8Array,
  offsets: Float64Array,
  sizes: Uint32Array,
  from: number,
  to: number,
): Uint8Array => {
  let total = 0;
  for (let i = from; i < to; i++) total += sizes[i];
  const out = new Uint8Array(total);
  let cursor = 0;
  for (let i = from; i < to; i++) {
    out.set(bytes.subarray(offsets[i], offsets[i] + sizes[i]), cursor);
    cursor += sizes[i];
  }
  return out;
};

describe('parseAudioTrack', () => {
  it.each([
    ['moov before mdat', MOOV_FIRST],
    ['moov after mdat', MOOV_LAST],
    ['mp4 with a video track', WITH_VIDEO],
  ])('finds the AAC track in a file with %s', async (_label, bytes) => {
    const track = await parseAudioTrack(memoryReader(bytes), bytes.length);
    expect(track.timescale).toBe(EXPECTED_TIMESCALE);
    expect(track.sampleCount).toBe(EXPECTED_SAMPLES);
    expect(track.durationS).toBeCloseTo(12.4, 0);
    expect(track.offsets.length).toBe(EXPECTED_SAMPLES);
    expect(track.sizes.length).toBe(EXPECTED_SAMPLES);
    expect(track.deltas.length).toBe(EXPECTED_SAMPLES);
    // stsd is a real box: size prefix then the 'stsd' tag
    expect(String.fromCharCode(...track.stsd.subarray(4, 8))).toBe('stsd');
    // every sample sits inside the file and has a plausible AAC packet size
    for (let i = 0; i < track.sampleCount; i++) {
      expect(track.offsets[i] + track.sizes[i]).toBeLessThanOrEqual(bytes.length);
      expect(track.sizes[i]).toBeGreaterThan(0);
      expect(track.sizes[i]).toBeLessThan(2000);
    }
  });

  it('locates a trailing moov with header-sized reads, never scanning mdat', async () => {
    const { read, spans } = recordingReader(MOOV_LAST);
    await parseAudioTrack(read, MOOV_LAST.length);
    const bytesRead = spans.reduce((sum, [s, e]) => sum + (e - s + 1), 0);
    // moov is 1,831 bytes; a handful of 16-byte header probes on top of it
    expect(bytesRead).toBeLessThan(2500);
    expect(spans.some(([s, e]) => e - s + 1 > 70_000)).toBe(false);
  });

  it('rejects a file without an audio track', async () => {
    const junk = new Uint8Array(64);
    await expect(parseAudioTrack(memoryReader(junk), junk.length)).rejects.toThrow(/no_moov/);
  });
});

describe('planChunks', () => {
  it('splits by bytes into consecutive runs that cover every sample', async () => {
    const track = await parseAudioTrack(memoryReader(MOOV_FIRST), MOOV_FIRST.length);
    const chunks = planChunks(track, { maxBytes: 30_000, maxSeconds: 3600 });
    expect(chunks.length).toBe(3);
    expect(chunks[0].firstSample).toBe(0);
    expect(chunks.at(-1)!.lastSample).toBe(track.sampleCount);
    for (let i = 1; i < chunks.length; i++) {
      expect(chunks[i].firstSample).toBe(chunks[i - 1].lastSample);
    }
    for (const c of chunks) {
      expect(c.bytes).toBeLessThanOrEqual(30_000);
      expect(c.bytes).toBeGreaterThan(0);
    }
    expect(chunks.reduce((n, c) => n + c.bytes, 0)).toBe(
      Array.from(track.sizes).reduce((a, b) => a + b, 0),
    );
  });

  it('splits by seconds and reports start offsets', async () => {
    const track = await parseAudioTrack(memoryReader(MOOV_FIRST), MOOV_FIRST.length);
    const chunks = planChunks(track, { maxBytes: 1e9, maxSeconds: 5 });
    expect(chunks.length).toBe(3);
    for (const c of chunks) expect(c.durationS).toBeLessThanOrEqual(5.01);
    expect(chunks[0].startS).toBe(0);
    expect(chunks[1].startS).toBeCloseTo(chunks[0].durationS, 3);
    expect(chunks.reduce((n, c) => n + c.durationS, 0)).toBeCloseTo(track.durationS, 3);
  });

  it('returns a single chunk when everything fits', async () => {
    const track = await parseAudioTrack(memoryReader(MOOV_FIRST), MOOV_FIRST.length);
    const chunks = planChunks(track, { maxBytes: 1e9, maxSeconds: 3600 });
    expect(chunks.length).toBe(1);
    expect(chunks[0]).toMatchObject({ index: 0, firstSample: 0, lastSample: track.sampleCount });
  });
});

describe('buildChunkFile', () => {
  it.each([
    ['moov-first m4a', MOOV_FIRST],
    ['moov-last m4a', MOOV_LAST],
    ['mp4 with video', WITH_VIDEO],
  ])('writes chunk files that round-trip with byte-identical samples (%s)', async (_label, bytes) => {
    const track = await parseAudioTrack(memoryReader(bytes), bytes.length);
    const chunks = planChunks(track, { maxBytes: 30_000, maxSeconds: 3600 });
    expect(chunks.length).toBeGreaterThan(1);

    for (const chunk of chunks) {
      const file = await buildChunkFile(memoryReader(bytes), track, chunk);
      // Valid ISO-BMFF: ftyp first, and no bigger than payload + a small moov
      expect(String.fromCharCode(...file.subarray(4, 8))).toBe('ftyp');
      expect(file.length).toBeLessThan(chunk.bytes + 2_000 + 12 * (chunk.lastSample - chunk.firstSample));

      const again = await parseAudioTrack(memoryReader(file), file.length);
      expect(again.timescale).toBe(track.timescale);
      expect(again.sampleCount).toBe(chunk.lastSample - chunk.firstSample);
      expect(Array.from(again.sizes)).toEqual(
        Array.from(track.sizes.subarray(chunk.firstSample, chunk.lastSample)),
      );
      expect(Array.from(again.deltas)).toEqual(
        Array.from(track.deltas.subarray(chunk.firstSample, chunk.lastSample)),
      );
      expect(again.stsd).toEqual(track.stsd);

      const expected = concatSamples(bytes, track.offsets, track.sizes, chunk.firstSample, chunk.lastSample);
      const actual = concatSamples(file, again.offsets, again.sizes, 0, again.sampleCount);
      expect(actual).toEqual(expected);
    }
  });

  it('fetches interleaved video in bounded range windows', async () => {
    const track = await parseAudioTrack(memoryReader(WITH_VIDEO), WITH_VIDEO.length);
    const [chunk] = planChunks(track, { maxBytes: 1e9, maxSeconds: 3600 });
    const { read, spans } = recordingReader(WITH_VIDEO);
    const file = await buildChunkFile(read, track, chunk, { windowBytes: 16 * 1024 });
    for (const [s, e] of spans) expect(e - s + 1).toBeLessThanOrEqual(16 * 1024);
    // audio is a small fraction of the file; the chunk file must not carry video bytes
    expect(file.length).toBeLessThan(WITH_VIDEO.length);
    const again = await parseAudioTrack(memoryReader(file), file.length);
    expect(again.sampleCount).toBe(track.sampleCount);
  });
});
