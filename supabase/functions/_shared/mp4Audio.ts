// ISO-BMFF (m4a / mp4 / mov) audio demux + remux, dependency-free and pure
// enough to run in an edge function or under vitest.
//
// Why: OpenAI's transcription endpoint caps uploads at 25 MiB and edge
// functions cannot run ffmpeg (256 MB, 2 s CPU). But splitting an AAC
// recording needs no decoding: `moov` carries the sample tables, `mdat`
// carries raw AAC packets. We read `moov` via HTTP Range requests, cut the
// sample list into runs that fit the cap, fetch each run's bytes in bounded
// windows, and wrap them in a minimal, valid m4a (the original `stsd` box is
// copied verbatim so decoders see the same codec configuration).
//
// Spec: docs/superpowers/specs/2026-09-09-long-audio-transcription-design.md

/** Reads bytes [start, endInclusive] of the source. */
export type ByteReader = (start: number, endInclusive: number) => Promise<Uint8Array>;

export interface AudioTrack {
  /** mdhd timescale — ticks per second for `deltas` */
  timescale: number;
  /** The track's whole `stsd` box, copied verbatim into every chunk file */
  stsd: Uint8Array;
  sampleCount: number;
  /** Absolute byte offset of each sample in the source file */
  offsets: Float64Array;
  sizes: Uint32Array;
  /** Duration of each sample in timescale ticks */
  deltas: Uint32Array;
  durationS: number;
  totalBytes: number;
}

export interface ChunkPlan {
  index: number;
  firstSample: number;
  /** exclusive */
  lastSample: number;
  bytes: number;
  durationS: number;
  startS: number;
}

export type Mp4ErrorCode =
  | 'no_moov'
  | 'no_audio_track'
  | 'bad_atom'
  | 'bad_sample_table'
  | 'unsupported_stz2';

export class Mp4Error extends Error {
  code: Mp4ErrorCode;
  constructor(code: Mp4ErrorCode, detail: string) {
    super(`${code}: ${detail}`);
    this.code = code;
    this.name = 'Mp4Error';
  }
}

export const memoryReader = (bytes: Uint8Array): ByteReader => (start, end) =>
  Promise.resolve(bytes.subarray(start, Math.min(end + 1, bytes.length)));

// ---- byte helpers -----------------------------------------------------------

const view = (b: Uint8Array) => new DataView(b.buffer, b.byteOffset, b.byteLength);
const u32 = (b: Uint8Array, o: number) => view(b).getUint32(o);
const u64 = (b: Uint8Array, o: number) => Number(view(b).getBigUint64(o));
const fourcc = (b: Uint8Array, o: number) =>
  String.fromCharCode(b[o], b[o + 1], b[o + 2], b[o + 3]);

interface Box {
  type: string;
  /** offset of the box header within the buffer */
  start: number;
  /** first byte after the header */
  contentStart: number;
  /** exclusive end of the box */
  end: number;
}

/** Enumerate the boxes laid out in buf[start, end). */
const children = (buf: Uint8Array, start: number, end: number): Box[] => {
  const out: Box[] = [];
  let off = start;
  while (off + 8 <= end) {
    let size = u32(buf, off);
    const type = fourcc(buf, off + 4);
    let hdr = 8;
    if (size === 1) {
      if (off + 16 > end) break;
      size = u64(buf, off + 8);
      hdr = 16;
    } else if (size === 0) {
      size = end - off;
    }
    if (size < hdr || off + size > end) {
      throw new Mp4Error('bad_atom', `${type} at ${off} claims ${size} bytes`);
    }
    out.push({ type, start: off, contentStart: off + hdr, end: off + size });
    off += size;
  }
  return out;
};

const child = (buf: Uint8Array, parent: Box, type: string): Box | undefined =>
  children(buf, parent.contentStart, parent.end).find((b) => b.type === type);

// ---- parsing ----------------------------------------------------------------

const MAX_TOP_LEVEL_ATOMS = 256;

/**
 * Walks the top-level atoms with header-sized reads until `moov` is found
 * (recorders commonly write it after a multi-megabyte `mdat`), reads `moov`
 * whole, and returns the first `soun` track's sample tables.
 */
export const parseAudioTrack = async (read: ByteReader, fileSize: number): Promise<AudioTrack> => {
  let off = 0;
  let moov: Uint8Array | null = null;
  for (let n = 0; n < MAX_TOP_LEVEL_ATOMS && off + 8 <= fileSize; n++) {
    const head = await read(off, Math.min(off + 15, fileSize - 1));
    if (head.length < 8) break;
    let size = u32(head, 0);
    const type = fourcc(head, 4);
    let hdr = 8;
    if (size === 1) {
      if (head.length < 16) break;
      size = u64(head, 8);
      hdr = 16;
    } else if (size === 0) {
      size = fileSize - off;
    }
    if (size < hdr) throw new Mp4Error('bad_atom', `${type} at ${off} claims ${size} bytes`);
    if (type === 'moov') {
      moov = await read(off, off + size - 1);
      break;
    }
    off += size;
  }
  if (!moov) throw new Mp4Error('no_moov', 'no moov atom found in the first 256 top-level atoms');

  const root: Box = { type: 'moov', start: 0, contentStart: 0, end: moov.length };
  const moovBox = children(moov, 0, moov.length).find((b) => b.type === 'moov') ?? root;

  for (const trak of children(moov, moovBox.contentStart, moovBox.end)) {
    if (trak.type !== 'trak') continue;
    const mdia = child(moov, trak, 'mdia');
    if (!mdia) continue;
    const hdlr = child(moov, mdia, 'hdlr');
    if (!hdlr || fourcc(moov, hdlr.contentStart + 8) !== 'soun') continue;
    const mdhd = child(moov, mdia, 'mdhd');
    const minf = child(moov, mdia, 'minf');
    const stbl = minf && child(moov, minf, 'stbl');
    if (!mdhd || !stbl) continue;
    return parseSampleTables(moov, mdhd, stbl);
  }
  throw new Mp4Error('no_audio_track', 'moov has no track with a soun handler');
};

const parseSampleTables = (buf: Uint8Array, mdhd: Box, stbl: Box): AudioTrack => {
  const mdhdVersion = buf[mdhd.contentStart];
  const timescale = u32(buf, mdhd.contentStart + (mdhdVersion === 1 ? 20 : 12));

  const stsd = child(buf, stbl, 'stsd');
  const stts = child(buf, stbl, 'stts');
  const stsc = child(buf, stbl, 'stsc');
  const stsz = child(buf, stbl, 'stsz');
  const stco = child(buf, stbl, 'stco') ?? child(buf, stbl, 'co64');
  if (child(buf, stbl, 'stz2') && !stsz) {
    throw new Mp4Error('unsupported_stz2', 'compact sample sizes are not supported');
  }
  if (!stsd || !stts || !stsc || !stsz || !stco) {
    throw new Mp4Error('bad_sample_table', 'stbl is missing stsd/stts/stsc/stsz/stco');
  }

  // stsz: fixed sample_size or a per-sample table
  const fixedSize = u32(buf, stsz.contentStart + 4);
  const sampleCount = u32(buf, stsz.contentStart + 8);
  const sizes = new Uint32Array(sampleCount);
  if (fixedSize !== 0) {
    sizes.fill(fixedSize);
  } else {
    for (let i = 0; i < sampleCount; i++) sizes[i] = u32(buf, stsz.contentStart + 12 + i * 4);
  }

  // stts: run-length (count, delta) → per-sample deltas
  const deltas = new Uint32Array(sampleCount);
  const sttsCount = u32(buf, stts.contentStart + 4);
  let s = 0;
  let lastDelta = 0;
  for (let e = 0; e < sttsCount && s < sampleCount; e++) {
    const count = u32(buf, stts.contentStart + 8 + e * 8);
    const delta = u32(buf, stts.contentStart + 12 + e * 8);
    lastDelta = delta;
    for (let k = 0; k < count && s < sampleCount; k++) deltas[s++] = delta;
  }
  while (s < sampleCount) deltas[s++] = lastDelta;

  // stsc: which chunks hold how many samples
  const stscCount = u32(buf, stsc.contentStart + 4);
  const stscEntries: Array<{ firstChunk: number; samplesPerChunk: number }> = [];
  for (let e = 0; e < stscCount; e++) {
    stscEntries.push({
      firstChunk: u32(buf, stsc.contentStart + 8 + e * 12),
      samplesPerChunk: u32(buf, stsc.contentStart + 12 + e * 12),
    });
  }

  // stco/co64: chunk byte offsets
  const chunkCount = u32(buf, stco.contentStart + 4);
  const wide = stco.type === 'co64';
  const offsets = new Float64Array(sampleCount);
  let sample = 0;
  let entry = 0;
  for (let c = 0; c < chunkCount && sample < sampleCount; c++) {
    while (entry + 1 < stscEntries.length && stscEntries[entry + 1].firstChunk <= c + 1) entry++;
    const perChunk = stscEntries[entry]?.samplesPerChunk ?? 0;
    let running = wide ? u64(buf, stco.contentStart + 8 + c * 8) : u32(buf, stco.contentStart + 8 + c * 4);
    for (let k = 0; k < perChunk && sample < sampleCount; k++) {
      offsets[sample] = running;
      running += sizes[sample];
      sample++;
    }
  }
  if (sample < sampleCount) {
    throw new Mp4Error('bad_sample_table', `chunk tables place ${sample} of ${sampleCount} samples`);
  }

  let ticks = 0;
  let totalBytes = 0;
  for (let i = 0; i < sampleCount; i++) {
    ticks += deltas[i];
    totalBytes += sizes[i];
  }

  return {
    timescale,
    stsd: buf.slice(stsd.start, stsd.end),
    sampleCount,
    offsets,
    sizes,
    deltas,
    durationS: timescale > 0 ? ticks / timescale : 0,
    totalBytes,
  };
};

// ---- planning ---------------------------------------------------------------

/**
 * Cuts the sample list into consecutive runs of at most `maxBytes` payload
 * and `maxSeconds` duration. Deterministic for a given track, so a job can
 * resume from chunk N after a restart and get the same boundaries.
 */
export const planChunks = (
  track: AudioTrack,
  { maxBytes, maxSeconds }: { maxBytes: number; maxSeconds: number },
): ChunkPlan[] => {
  const maxTicks = maxSeconds * track.timescale;
  const chunks: ChunkPlan[] = [];
  let first = 0;
  let bytes = 0;
  let ticks = 0;
  let startTicks = 0;

  const close = (last: number) => {
    chunks.push({
      index: chunks.length,
      firstSample: first,
      lastSample: last,
      bytes,
      durationS: ticks / track.timescale,
      startS: startTicks / track.timescale,
    });
    startTicks += ticks;
    first = last;
    bytes = 0;
    ticks = 0;
  };

  for (let i = 0; i < track.sampleCount; i++) {
    const size = track.sizes[i];
    const delta = track.deltas[i];
    if (i > first && (bytes + size > maxBytes || ticks + delta > maxTicks)) close(i);
    bytes += size;
    ticks += delta;
  }
  if (track.sampleCount > first) close(track.sampleCount);
  return chunks;
};

// ---- fetching + muxing ------------------------------------------------------

const DEFAULT_WINDOW_BYTES = 8 * 1024 * 1024;

/**
 * Fetches one chunk's samples in bounded range windows and returns a
 * standalone m4a file containing just those samples.
 */
export const buildChunkFile = async (
  read: ByteReader,
  track: AudioTrack,
  chunk: ChunkPlan,
  opts: { windowBytes?: number } = {},
): Promise<Uint8Array> => {
  const windowBytes = opts.windowBytes ?? DEFAULT_WINDOW_BYTES;
  const payload = new Uint8Array(chunk.bytes);
  let cursor = 0;
  let i = chunk.firstSample;
  while (i < chunk.lastSample) {
    const windowStart = track.offsets[i];
    let windowEnd = windowStart + track.sizes[i];
    let j = i + 1;
    while (
      j < chunk.lastSample &&
      track.offsets[j] >= windowStart &&
      track.offsets[j] + track.sizes[j] - windowStart <= windowBytes
    ) {
      windowEnd = Math.max(windowEnd, track.offsets[j] + track.sizes[j]);
      j++;
    }
    const buf = await read(windowStart, windowEnd - 1);
    if (buf.length < windowEnd - windowStart) {
      throw new Mp4Error('bad_sample_table', `short read at ${windowStart}: wanted ${windowEnd - windowStart}, got ${buf.length}`);
    }
    for (let k = i; k < j; k++) {
      const rel = track.offsets[k] - windowStart;
      payload.set(buf.subarray(rel, rel + track.sizes[k]), cursor);
      cursor += track.sizes[k];
    }
    i = j;
  }
  return muxM4a(
    track,
    track.sizes.subarray(chunk.firstSample, chunk.lastSample),
    track.deltas.subarray(chunk.firstSample, chunk.lastSample),
    payload,
  );
};

const ascii = (s: string) => new TextEncoder().encode(s);

const concat = (parts: Uint8Array[]): Uint8Array => {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let o = 0;
  for (const p of parts) {
    out.set(p, o);
    o += p.length;
  }
  return out;
};

const be32 = (...values: number[]): Uint8Array => {
  const out = new Uint8Array(values.length * 4);
  const dv = view(out);
  values.forEach((v, i) => dv.setUint32(i * 4, v >>> 0));
  return out;
};

const be16 = (...values: number[]): Uint8Array => {
  const out = new Uint8Array(values.length * 2);
  const dv = view(out);
  values.forEach((v, i) => dv.setUint16(i * 2, v & 0xffff));
  return out;
};

const box = (type: string, ...parts: Uint8Array[]): Uint8Array => {
  const body = concat(parts);
  return concat([be32(body.length + 8), ascii(type), body]);
};

const fullBox = (type: string, version: number, flags: number, ...parts: Uint8Array[]): Uint8Array =>
  box(type, be32(((version & 0xff) << 24) | (flags & 0xffffff)), ...parts);

// identity transform matrix, as mvhd/tkhd expect it
const UNITY_MATRIX = be32(0x00010000, 0, 0, 0, 0x00010000, 0, 0, 0, 0x40000000);

/** Wraps AAC samples in a minimal single-track m4a. `stsd` is the source's. */
export const muxM4a = (
  track: Pick<AudioTrack, 'timescale' | 'stsd'>,
  sizes: Uint32Array,
  deltas: Uint32Array,
  payload: Uint8Array,
): Uint8Array => {
  const n = sizes.length;
  let duration = 0;
  for (let i = 0; i < n; i++) duration += deltas[i];
  if (duration > 0xffffffff) duration = 0xffffffff;

  // stts as run-length pairs
  const runs: number[] = [];
  for (let i = 0; i < n; i++) {
    if (runs.length && runs[runs.length - 1] === deltas[i]) runs[runs.length - 2]++;
    else runs.push(1, deltas[i]);
  }

  const ftyp = box('ftyp', ascii('M4A '), be32(0), ascii('M4A '), ascii('mp42'), ascii('isom'));

  const mvhd = fullBox(
    'mvhd', 0, 0,
    be32(0, 0, track.timescale, duration, 0x00010000), // times, timescale, duration, rate
    be16(0x0100, 0), // volume, reserved
    new Uint8Array(8), // reserved
    UNITY_MATRIX,
    new Uint8Array(24), // pre_defined
    be32(2), // next_track_ID
  );

  const tkhd = fullBox(
    'tkhd', 0, 0x7,
    be32(0, 0, 1, 0, duration), // times, track_ID, reserved, duration
    new Uint8Array(8), // reserved
    be16(0, 0, 0x0100, 0), // layer, alternate_group, volume, reserved
    UNITY_MATRIX,
    be32(0, 0), // width, height
  );

  const mdhd = fullBox('mdhd', 0, 0, be32(0, 0, track.timescale, duration), be16(0x55c4, 0));
  const hdlr = fullBox('hdlr', 0, 0, be32(0), ascii('soun'), new Uint8Array(12), ascii('SoundHandler\0'));
  const smhd = fullBox('smhd', 0, 0, be16(0, 0));
  const dinf = box('dinf', fullBox('dref', 0, 0, be32(1), fullBox('url ', 0, 1)));

  const stts = fullBox('stts', 0, 0, be32(runs.length / 2), be32(...runs));
  const stsc = fullBox('stsc', 0, 0, be32(1), be32(1, n, 1));
  const stszSizes = new Uint8Array(n * 4);
  const dv = view(stszSizes);
  for (let i = 0; i < n; i++) dv.setUint32(i * 4, sizes[i]);
  const stsz = fullBox('stsz', 0, 0, be32(0, n), stszSizes);
  const stco = fullBox('stco', 0, 0, be32(1), be32(0)); // offset patched below

  const stbl = box('stbl', track.stsd, stts, stsc, stsz, stco);
  const minf = box('minf', smhd, dinf, stbl);
  const mdia = box('mdia', mdhd, hdlr, minf);
  const trak = box('trak', tkhd, mdia);
  const moov = box('moov', mvhd, trak);

  // stco is the last box in moov, so its single entry is moov's last 4 bytes
  const mdatPayloadOffset = ftyp.length + moov.length + 8;
  view(moov).setUint32(moov.length - 4, mdatPayloadOffset);

  return concat([ftyp, moov, box('mdat', payload)]);
};
