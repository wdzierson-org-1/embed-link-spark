// @vitest-environment node
import { describe, expect, it } from 'vitest';
import {
  META_BYTES_LIMIT,
  afterDraining,
  MULTIPART_BODY_LIMIT,
  ONE_SHOT_FILE_LIMIT,
  RECEIPT_HEARTBEAT_MS,
  RECEIPT_TAKEOVER_MS,
  SETTLE_ATTEMPTS,
  SETTLE_BACKOFF_MS,
  decideReceipt,
  downstreamBodyFor,
  downstreamPathFor,
  drainStream,
  exceedsDeclaredLength,
  exceedsMultipartBodyLimit,
  fileExtensionFor,
  interpretFencedWrite,
  normalizeDownstreamItem,
  parseCaptureMeta,
  readCappedBytes,
  requestBodyKind,
  settleFailure,
  settleSuccess,
  storedObjectPath,
  type AttemptStore,
  type CaptureMeta,
  type WriteResult,
} from './capture';

const UID = '6f1c2d3e-4b5a-4c6d-8e7f-001122334455';
const CID = 'a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d';
const json = { userId: UID, hasFile: false };
const multipart = { userId: UID, hasFile: true };

const ok = (raw: unknown, ctx = json) => {
  const result = parseCaptureMeta(raw, ctx);
  if (!result.ok) throw new Error(`expected ok, got: ${result.error}`);
  return result;
};
const errorOf = (raw: unknown, ctx = json) => {
  const result = parseCaptureMeta(raw, ctx);
  if (result.ok) throw new Error('expected a validation error');
  return result.error;
};

describe('parseCaptureMeta — envelope', () => {
  it('rejects anything that is not a JSON object', () => {
    expect(errorOf(null)).toBe('meta must be a JSON object');
    expect(errorOf([{ capture_id: CID }])).toBe('meta must be a JSON object');
    expect(errorOf('{"capture_id":"x"}')).toBe('meta must be a JSON object');
  });

  it('requires a UUID capture_id and lowercases it', () => {
    expect(errorOf({ kind: 'note', content: 'x' })).toBe('capture_id is required');
    expect(errorOf({ capture_id: '', kind: 'note', content: 'x' })).toBe('capture_id is required');
    expect(errorOf({ capture_id: null, kind: 'note', content: 'x' })).toBe('capture_id is required');
    expect(errorOf({ capture_id: 'not-a-uuid', kind: 'note', content: 'x' })).toBe('capture_id must be a UUID');
    expect(errorOf({ capture_id: 42, kind: 'note', content: 'x' })).toBe('capture_id must be a UUID');
    expect(errorOf({ capture_id: `${CID}0`, kind: 'note', content: 'x' })).toBe('capture_id must be a UUID');
    expect(ok({ capture_id: CID.toUpperCase(), kind: 'note', content: 'x' }).meta.capture_id).toBe(CID);
  });

  it('requires a known kind', () => {
    expect(errorOf({ capture_id: CID, content: 'x' })).toBe('kind is required');
    expect(errorOf({ capture_id: CID, kind: 'photo' })).toBe('kind must be one of note, url, file');
    expect(errorOf({ capture_id: CID, kind: 3 })).toBe('kind must be one of note, url, file');
  });

  it('type-checks optional string fields, treating null as absent', () => {
    expect(errorOf({ capture_id: CID, kind: 'note', content: 7 })).toBe('content must be a string');
    expect(errorOf({ capture_id: CID, kind: 'note', content: 'x', title: ['t'] })).toBe('title must be a string');
    const { meta } = ok({ capture_id: CID, kind: 'note', content: 'x', title: null });
    expect('title' in meta).toBe(false);
  });

  it('defaults is_public to false and rejects non-booleans', () => {
    expect(ok({ capture_id: CID, kind: 'note', content: 'x' }).meta.is_public).toBe(false);
    expect(ok({ capture_id: CID, kind: 'note', content: 'x', is_public: null }).meta.is_public).toBe(false);
    expect(ok({ capture_id: CID, kind: 'note', content: 'x', is_public: true }).meta.is_public).toBe(true);
    expect(errorOf({ capture_id: CID, kind: 'note', content: 'x', is_public: 'yes' })).toBe('is_public must be a boolean');
  });
});

describe('parseCaptureMeta — metadata never fails a capture', () => {
  const base = { capture_id: CID, kind: 'note', content: 'x' };

  it('keeps a non-empty attributes object verbatim and drops {} silently', () => {
    const attributes = { location: { lat: 1, lng: 2, label: 'Here' }, media: { file_name: 'a.jpg' } };
    expect(ok({ ...base, attributes }).meta.attributes).toEqual(attributes);
    const empty = ok({ ...base, attributes: {} });
    expect('attributes' in empty.meta).toBe(false);
    expect(empty.warnings).toEqual([]);
  });

  it('drops non-object attributes with a warning', () => {
    const result = ok({ ...base, attributes: [1, 2] });
    expect('attributes' in result.meta).toBe(false);
    expect(result.warnings).toEqual(['attributes ignored: not a JSON object']);
    expect(ok({ ...base, attributes: 'x' }).warnings).toHaveLength(1);
    expect(ok({ ...base, attributes: null }).warnings).toEqual([]);
  });

  it('forwards a string remind_at verbatim and drops anything else with a warning', () => {
    expect(ok({ ...base, remind_at: '2026-10-01T09:00:00-04:00' }).meta.remind_at).toBe('2026-10-01T09:00:00-04:00');
    expect(ok({ ...base, remind_at: 'garbage' }).meta.remind_at).toBe('garbage');
    const numeric = ok({ ...base, remind_at: 1760000000 });
    expect('remind_at' in numeric.meta).toBe(false);
    expect(numeric.warnings).toEqual(['remind_at ignored: not a string']);
  });
});

describe('parseCaptureMeta — note', () => {
  it.each([
    'https://youtube.com/watch?v=abc123XYZ_0&si=share-token',
    'https://youtu.be/abc123XYZ_0?t=35',
    'http://example.com/article?variant=navy#details',
  ])('routes a whole URL supplied as a note through link enrichment: %s', (url) => {
    const { meta } = ok({ capture_id: CID.toUpperCase(), kind: 'note', content: ` \n${url}\n ` });
    expect(meta).toEqual({ capture_id: CID, kind: 'url', url, is_public: false });
    expect(downstreamPathFor(meta.kind)).toBe('add-url');
    expect(downstreamBodyFor(meta)).toEqual({ url, is_public: false });
  });

  it('preserves privacy, attributes, reminder and receipt identity when promoting a URL-only note', () => {
    const url = 'https://youtube.com/watch?v=abc123XYZ_0';
    const attributes = { capture: { origin: 'ios_share_sheet' } };
    const remind_at = '2026-10-15T09:00:00-04:00';
    const { meta } = ok({ capture_id: CID, kind: 'note', content: url, title: 'Shared text', is_public: true, attributes, remind_at });
    expect(meta.capture_id).toBe(CID);
    expect(downstreamBodyFor(meta)).toEqual({ url, is_public: true, attributes, remind_at });
  });

  it.each([
    'Watch this https://youtube.com/watch?v=abc123XYZ_0',
    'https://youtube.com/watch?v=abc123XYZ_0\nA video to watch',
    'https://youtu.be/abc123XYZ_0\nhttps://youtu.be/otherVideo0',
    'https://example.com/a https://example.com/b',
    'https://example.com/a\tb',
    'https://example.com/a\\b',
    'https://',
    'https:///example.com',
    'https://example.com/<video>',
    'https:example.com',
    'https://user:password@example.com',
    'ftp://example.com/video',
    'javascript:alert(1)',
    'youtube.com/watch?v=abc123XYZ_0',
  ])('preserves ordinary or ambiguous note content: %s', (content) => {
    const { meta } = ok({ capture_id: CID, kind: 'note', content });
    expect(meta.kind).toBe('note');
    expect(meta.content).toBe(content);
    expect(meta.url).toBeUndefined();
    expect(downstreamPathFor(meta.kind)).toBe('add-note');
  });

  it('requires non-blank content and keeps it untrimmed', () => {
    expect(errorOf({ capture_id: CID, kind: 'note' })).toBe('content is required for a note');
    expect(errorOf({ capture_id: CID, kind: 'note', content: '   \n' })).toBe('content is required for a note');
    const { meta } = ok({ capture_id: CID, kind: 'note', content: '  hello  ', title: 'T' });
    expect(meta).toEqual({ capture_id: CID, kind: 'note', content: '  hello  ', title: 'T', is_public: false });
  });

  it('refuses a multipart file part on a non-file kind', () => {
    expect(errorOf({ capture_id: CID, kind: 'note', content: 'x' }, multipart)).toBe('a file part is only accepted with kind "file"');
    expect(errorOf({ capture_id: CID, kind: 'url', url: 'https://a.b' }, multipart)).toBe('a file part is only accepted with kind "file"');
  });
});

describe('parseCaptureMeta — url', () => {
  it('requires a parseable url', () => {
    expect(errorOf({ capture_id: CID, kind: 'url' })).toBe('url is required for kind "url"');
    expect(errorOf({ capture_id: CID, kind: 'url', url: '  ' })).toBe('url is required for kind "url"');
    expect(errorOf({ capture_id: CID, kind: 'url', url: 'not a url' })).toBe('url is not a valid URL');
    const { meta } = ok({ capture_id: CID, kind: 'url', url: 'https://example.com/a?b=1', content: 'why' });
    expect(meta).toEqual({ capture_id: CID, kind: 'url', url: 'https://example.com/a?b=1', content: 'why', is_public: false });
  });
});

describe('parseCaptureMeta — file', () => {
  const twoStep = { capture_id: CID, kind: 'file', mime_type: 'image/jpeg', file_path: `${UID}/${CID}.jpg` };

  it('requires a mime_type that looks like type/subtype and normalises it', () => {
    expect(errorOf({ ...twoStep, mime_type: undefined })).toBe('mime_type is required for kind "file"');
    expect(errorOf({ ...twoStep, mime_type: '  ' })).toBe('mime_type is required for kind "file"');
    expect(errorOf({ ...twoStep, mime_type: 'jpeg' })).toBe('mime_type must look like type/subtype');
    expect(ok({ ...twoStep, mime_type: ' Image/JPEG ' }).meta.mime_type).toBe('image/jpeg');
    expect(ok({ ...twoStep, mime_type: 'text/plain; charset=utf-8' }).meta.mime_type).toBe('text/plain; charset=utf-8');
  });

  it('two-step: requires a file_path inside the caller folder with clean segments', () => {
    expect(errorOf({ ...twoStep, file_path: undefined })).toBe('file_path is required when no file part is sent');
    expect(errorOf({ ...twoStep, file_path: `someone-else/${CID}.jpg` })).toBe('file_path must be inside your own storage folder');
    expect(errorOf({ ...twoStep, file_path: `${UID}x/${CID}.jpg` })).toBe('file_path must be inside your own storage folder');
    expect(errorOf({ ...twoStep, file_path: `${UID}/` })).toBe('file_path contains invalid segments');
    expect(errorOf({ ...twoStep, file_path: `${UID}/../other/${CID}.jpg` })).toBe('file_path contains invalid segments');
    expect(errorOf({ ...twoStep, file_path: `${UID}//x.jpg` })).toBe('file_path contains invalid segments');
    expect(ok(twoStep).meta.file_path).toBe(`${UID}/${CID}.jpg`);
  });

  it('multipart: the file part replaces file_path, and sending both is ambiguous', () => {
    const { file_path: _ignored, ...oneShot } = twoStep;
    expect('file_path' in ok(oneShot, multipart).meta).toBe(false);
    expect(errorOf(twoStep, multipart)).toBe('send either a file part or file_path, not both');
  });

  it('keeps file_name and a valid file_size; drops a bad file_size with a warning', () => {
    const good = ok({ ...twoStep, file_name: 'IMG_0001.HEIC', file_size: 1234 });
    expect(good.meta.file_name).toBe('IMG_0001.HEIC');
    expect(good.meta.file_size).toBe(1234);
    expect(ok({ ...twoStep, file_size: 0 }).meta.file_size).toBe(0);
    for (const bad of [-1, 1.5, '12', Number.NaN]) {
      const result = ok({ ...twoStep, file_size: bad });
      expect('file_size' in result.meta).toBe(false);
      expect(result.warnings).toEqual(['file_size ignored: not a non-negative integer']);
    }
    expect(ok({ ...twoStep, file_size: null }).warnings).toEqual([]);
  });
});

describe('fileExtensionFor', () => {
  it('prefers a sane extension from the file name, lowercased', () => {
    expect(fileExtensionFor('Photo.JPG', 'image/png')).toBe('jpg');
    expect(fileExtensionFor('IMG_0001.HEIC', null)).toBe('heic');
    expect(fileExtensionFor('archive.tar.gz', 'application/gzip')).toBe('gz');
    expect(fileExtensionFor('folder/sub/report.pdf', null)).toBe('pdf');
  });

  it('falls back to the MIME map when the name has no usable extension', () => {
    expect(fileExtensionFor('noext', 'image/png')).toBe('png');
    expect(fileExtensionFor('.hidden', 'image/png')).toBe('png');
    expect(fileExtensionFor('trailingdot.', 'application/pdf')).toBe('pdf');
    expect(fileExtensionFor('weird.ex-t', 'audio/x-m4a')).toBe('m4a');
    expect(fileExtensionFor('long.abcdefghijk', 'video/quicktime')).toBe('mov');
    expect(fileExtensionFor(undefined, 'IMAGE/JPEG; q=1')).toBe('jpg');
    expect(fileExtensionFor(null, 'application/vnd.openxmlformats-officedocument.wordprocessingml.document')).toBe('docx');
  });

  it('ends at bin when nothing is known', () => {
    expect(fileExtensionFor(null, null)).toBe('bin');
    expect(fileExtensionFor('', 'application/x-unknown')).toBe('bin');
  });
});

describe('storedObjectPath', () => {
  it('is <uid>/<capture_id>.<ext> with a lowercase id', () => {
    expect(storedObjectPath(UID, CID.toUpperCase(), 'png')).toBe(`${UID}/${CID}.png`);
  });
});

describe('decideReceipt', () => {
  const now = Date.parse('2026-09-27T12:00:00.000Z');
  const ago = (ms: number) => new Date(now - ms).toISOString();

  it('proceeds when there is no receipt', () => {
    expect(decideReceipt(null, now)).toEqual({ action: 'proceed' });
    expect(decideReceipt(undefined, now)).toEqual({ action: 'proceed' });
  });

  it('returns the recorded item for a done receipt (null once the item was deleted)', () => {
    expect(decideReceipt({ status: 'done', item_id: 'item-1', updated_at: ago(10 * 60_000) }, now))
      .toEqual({ action: 'duplicate', itemId: 'item-1' });
    expect(decideReceipt({ status: 'done', item_id: null, updated_at: ago(1_000) }, now))
      .toEqual({ action: 'duplicate', itemId: null });
  });

  it('treats a pending receipt younger than 120 s as in progress', () => {
    expect(decideReceipt({ status: 'pending', item_id: null, updated_at: ago(0) }, now)).toEqual({ action: 'inProgress' });
    expect(decideReceipt({ status: 'pending', item_id: null, updated_at: ago(RECEIPT_TAKEOVER_MS - 1) }, now))
      .toEqual({ action: 'inProgress' });
    // clock skew: a receipt stamped slightly in the future is still live
    expect(decideReceipt({ status: 'pending', item_id: null, updated_at: ago(-2_000) }, now)).toEqual({ action: 'inProgress' });
  });

  it('takes over a pending receipt at or past 120 s, or with an unreadable timestamp', () => {
    expect(decideReceipt({ status: 'pending', item_id: null, updated_at: ago(RECEIPT_TAKEOVER_MS) }, now))
      .toEqual({ action: 'takeOver' });
    expect(decideReceipt({ status: 'pending', item_id: null, updated_at: ago(30 * 60_000) }, new Date(now)))
      .toEqual({ action: 'takeOver' });
    expect(decideReceipt({ status: 'pending', item_id: null, updated_at: 'garbage' }, now)).toEqual({ action: 'takeOver' });
  });

  it('accepts Postgres-style timestamps with microseconds and an offset', () => {
    expect(decideReceipt({ status: 'pending', item_id: null, updated_at: '2026-09-27T11:59:30.123456+00:00' }, now))
      .toEqual({ action: 'inProgress' });
    expect(decideReceipt({ status: 'pending', item_id: null, updated_at: '2026-09-27T11:57:59.999999+00:00' }, now))
      .toEqual({ action: 'takeOver' });
  });

  it('heartbeats well inside the takeover window', () => {
    expect(RECEIPT_HEARTBEAT_MS * 3).toBeLessThan(RECEIPT_TAKEOVER_MS);
  });
});

describe('downstreamPathFor', () => {
  it('routes each kind to its existing endpoint', () => {
    expect(downstreamPathFor('note')).toBe('add-note');
    expect(downstreamPathFor('url')).toBe('add-url');
    expect(downstreamPathFor('file')).toBe('add-file');
  });
});

describe('downstreamBodyFor', () => {
  const noUndefined = (body: Record<string, unknown>) =>
    expect(Object.values(body).every((value) => value !== undefined)).toBe(true);

  it('url → {url, content?, is_public, attributes?, remind_at?} and never a title', () => {
    const minimal = downstreamBodyFor({ capture_id: CID, kind: 'url', url: 'https://a.b/c', is_public: false });
    expect(minimal).toEqual({ url: 'https://a.b/c', is_public: false });
    expect(Object.keys(minimal)).toEqual(['url', 'is_public']);

    const full = downstreamBodyFor({
      capture_id: CID,
      kind: 'url',
      url: 'https://a.b/c',
      content: 'read later',
      title: 'Ignored for links',
      is_public: true,
      attributes: { location: { lat: 1, lng: 2 } },
      remind_at: '2026-10-01T09:00:00Z',
    });
    expect(full).toEqual({
      url: 'https://a.b/c',
      content: 'read later',
      is_public: true,
      attributes: { location: { lat: 1, lng: 2 } },
      remind_at: '2026-10-01T09:00:00Z',
    });
    noUndefined(full);
  });

  it('note → {content, title?, is_public, attributes?, remind_at?}', () => {
    expect(downstreamBodyFor({ capture_id: CID, kind: 'note', content: 'hi', is_public: false }))
      .toEqual({ content: 'hi', is_public: false });
    const full = downstreamBodyFor({
      capture_id: CID, kind: 'note', content: 'hi', title: 'T', is_public: false,
      attributes: { x: 1 }, remind_at: '2026-10-01T09:00:00Z',
    });
    expect(full).toEqual({ content: 'hi', title: 'T', is_public: false, attributes: { x: 1 }, remind_at: '2026-10-01T09:00:00Z' });
  });

  it('file (multipart) → uses the stored path; omits what was not sent', () => {
    const meta: CaptureMeta = { capture_id: CID, kind: 'file', mime_type: 'image/png', is_public: false };
    const body = downstreamBodyFor(meta, `${UID}/${CID}.png`);
    expect(body).toEqual({ file_path: `${UID}/${CID}.png`, mime_type: 'image/png', is_public: false });
    noUndefined(body);
  });

  it('file (two-step) → uses the meta file_path, with every optional field', () => {
    const body = downstreamBodyFor({
      capture_id: CID, kind: 'file', mime_type: 'application/pdf', file_path: `${UID}/${CID}.pdf`,
      file_size: 99, file_name: 'Report.pdf', content: 'note', title: 'Report', is_public: false,
      attributes: { media: { file_name: 'Report.pdf' } }, remind_at: '2026-10-01T09:00:00Z',
    });
    expect(body).toEqual({
      file_path: `${UID}/${CID}.pdf`, mime_type: 'application/pdf', file_size: 99, content: 'note', title: 'Report',
      is_public: false, attributes: { media: { file_name: 'Report.pdf' } }, remind_at: '2026-10-01T09:00:00Z',
    });
    expect('file_name' in body).toBe(false);
  });

  it('never sends attributes: {} and refuses a file capture with no path', () => {
    const body = downstreamBodyFor({ capture_id: CID, kind: 'note', content: 'x', is_public: false, attributes: {} });
    expect('attributes' in body).toBe(false);
    expect(() => downstreamBodyFor({ capture_id: CID, kind: 'file', mime_type: 'image/png', is_public: false }))
      .toThrow(/stored path or file_path/);
  });

  it('parse → build round trip for a typical share-sheet link', () => {
    const { meta } = ok({
      capture_id: CID.toUpperCase(), kind: 'url', url: 'https://example.com', content: '', is_public: false,
      attributes: {}, remind_at: null, file_size: 5,
    });
    expect(downstreamBodyFor(meta)).toEqual({ url: 'https://example.com', content: '', is_public: false });
  });
});

describe('normalizeDownstreamItem', () => {
  it('reads {item} (add-url, add-file) and {note} (add-note)', () => {
    expect(normalizeDownstreamItem({ success: true, item: { id: 'i1' } })).toEqual({ id: 'i1' });
    expect(normalizeDownstreamItem({ success: true, note: { id: 'n1' }, message: 'ok' })).toEqual({ id: 'n1' });
  });

  it('returns null for anything else', () => {
    expect(normalizeDownstreamItem(null)).toBeNull();
    expect(normalizeDownstreamItem({})).toBeNull();
    expect(normalizeDownstreamItem({ item: 'nope' })).toBeNull();
    expect(normalizeDownstreamItem([{ id: 'x' }])).toBeNull();
  });
});

describe('requestBodyKind', () => {
  it('recognises JSON (default when absent) and multipart, case-insensitively', () => {
    expect(requestBodyKind('application/json')).toBe('json');
    expect(requestBodyKind('application/json; charset=utf-8')).toBe('json');
    expect(requestBodyKind(null)).toBe('json');
    expect(requestBodyKind('')).toBe('json');
    expect(requestBodyKind('multipart/form-data; boundary=abc')).toBe('multipart');
    expect(requestBodyKind('MULTIPART/FORM-DATA; boundary=abc')).toBe('multipart');
  });

  it('rejects other content types', () => {
    expect(requestBodyKind('text/plain')).toBeNull();
    expect(requestBodyKind('application/x-www-form-urlencoded')).toBeNull();
  });
});

describe('multipart size limits', () => {
  it('one-shot files go up to 45 MiB; the body limit adds room for meta + boundaries', () => {
    expect(ONE_SHOT_FILE_LIMIT).toBe(47_185_920);
    expect(MULTIPART_BODY_LIMIT).toBeGreaterThan(ONE_SHOT_FILE_LIMIT);
    expect(MULTIPART_BODY_LIMIT - ONE_SHOT_FILE_LIMIT).toBe(1024 * 1024);
  });

  it('flags only a declared Content-Length over the limit', () => {
    expect(exceedsMultipartBodyLimit(String(MULTIPART_BODY_LIMIT))).toBe(false);
    expect(exceedsMultipartBodyLimit(String(MULTIPART_BODY_LIMIT + 1))).toBe(true);
    expect(exceedsMultipartBodyLimit(' 60000000 ')).toBe(true);
    expect(exceedsMultipartBodyLimit('0')).toBe(false);
    expect(exceedsMultipartBodyLimit(null)).toBe(false);
    expect(exceedsMultipartBodyLimit('abc')).toBe(false);
    expect(exceedsMultipartBodyLimit('-5')).toBe(false);
    expect(exceedsMultipartBodyLimit('101', 100)).toBe(true);
  });

  it('caps JSON meta at 1 MiB by declared length', () => {
    expect(META_BYTES_LIMIT).toBe(1_048_576);
    expect(exceedsDeclaredLength(String(META_BYTES_LIMIT), META_BYTES_LIMIT)).toBe(false);
    expect(exceedsDeclaredLength(String(META_BYTES_LIMIT + 1), META_BYTES_LIMIT)).toBe(true);
    expect(exceedsDeclaredLength(undefined, META_BYTES_LIMIT)).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Body streams

const streamOf = (chunks: Uint8Array[]) => {
  let pulled = 0;
  const stream = new ReadableStream<Uint8Array>({
    pull(controller) {
      if (pulled < chunks.length) controller.enqueue(chunks[pulled++]);
      else controller.close();
    },
  });
  return { stream, pulled: () => pulled };
};
const bytes = (n: number, fill = 1) => new Uint8Array(n).fill(fill);

describe('drainStream', () => {
  it('reads a body to the end without keeping it', async () => {
    const { stream, pulled } = streamOf([bytes(10), bytes(20), bytes(30)]);
    expect(await drainStream(stream, 1_000)).toBe(60);
    expect(pulled()).toBe(3);
  });

  it('stops once past the cap, and tolerates no body or a locked one', async () => {
    const { stream, pulled } = streamOf(Array.from({ length: 50 }, () => bytes(10)));
    const seen = await drainStream(stream, 25);
    expect(seen).toBeGreaterThan(25);
    expect(pulled()).toBeLessThan(10);
    expect(await drainStream(null, 10)).toBe(0);
    const locked = streamOf([bytes(1)]).stream;
    locked.getReader();
    expect(await drainStream(locked, 10)).toBe(0);
  });
});

describe('readCappedBytes', () => {
  it('returns the concatenated body when within the limit', async () => {
    const { stream } = streamOf([new Uint8Array([1, 2]), new Uint8Array([3]), new Uint8Array([4, 5, 6])]);
    const read = await readCappedBytes(stream, 6, 100);
    expect(read).toEqual({ kind: 'ok', bytes: new Uint8Array([1, 2, 3, 4, 5, 6]) });
    expect(await readCappedBytes(null, 6, 100)).toEqual({ kind: 'ok', bytes: new Uint8Array(0) });
  });

  it('answers tooLarge past the limit after draining the rest of the body', async () => {
    const { stream, pulled } = streamOf([bytes(4), bytes(4), bytes(4), bytes(4)]);
    expect(await readCappedBytes(stream, 6, 1_000)).toEqual({ kind: 'tooLarge' });
    expect(pulled()).toBe(4);
  });

  it('gives up draining past the drain cap', async () => {
    const { stream, pulled } = streamOf(Array.from({ length: 100 }, () => bytes(10)));
    expect(await readCappedBytes(stream, 15, 40)).toEqual({ kind: 'tooLarge' });
    expect(pulled()).toBeLessThan(10);
  });
});

// ---------------------------------------------------------------------------
// Attempt fencing

type Op = 'finalize' | 'release' | 'touch' | 'deleteItem' | 'removeObject';
type Scripted = WriteResult | Error;
const OWNED: WriteResult = { ok: true, rows: 1 };
const FENCED_OUT: WriteResult = { ok: true, rows: 0 };
const TRANSIENT: WriteResult = { ok: false, code: '57014', message: 'canceling statement due to statement timeout' };

/** Answers each op from a queue (the last entry repeats; default OWNED) and records calls, sleeps and logs. */
class ScriptedStore implements AttemptStore {
  calls: { op: Op; arg?: string | null }[] = [];
  sleeps: number[] = [];
  logs: { level: string; message: string; fields?: Record<string, unknown> }[] = [];
  constructor(private script: Partial<Record<Op, Scripted[]>> = {}) {}
  private next(op: Op, arg?: string | null): Promise<WriteResult> {
    this.calls.push({ op, arg });
    const queue = this.script[op] ?? [];
    const answer = queue.length > 1 ? queue.shift()! : queue[0] ?? OWNED;
    if (answer instanceof Error) throw answer;
    return Promise.resolve(answer);
  }
  finalize(itemId: string | null) { return this.next('finalize', itemId); }
  release() { return this.next('release'); }
  touch() { return this.next('touch'); }
  deleteItem(itemId: string) { return this.next('deleteItem', itemId); }
  removeObject(path: string) { return this.next('removeObject', path); }
  sleep(ms: number) { this.sleeps.push(ms); return Promise.resolve(); }
  log(level: 'log' | 'warn' | 'error', message: string, fields?: Record<string, unknown>) {
    this.logs.push({ level, message, fields });
  }
  ops(op: Op) { return this.calls.filter((c) => c.op === op); }
}

describe('interpretFencedWrite', () => {
  it('maps affected rows and errors to a verdict', () => {
    expect(interpretFencedWrite(OWNED)).toBe('owned');
    expect(interpretFencedWrite({ ok: true, rows: 2 })).toBe('owned');
    expect(interpretFencedWrite(FENCED_OUT)).toBe('superseded');
    expect(interpretFencedWrite({ ok: false, code: '23503', message: 'fk' })).toBe('itemGone');
    expect(interpretFencedWrite(TRANSIENT)).toBe('error');
    expect(interpretFencedWrite({ ok: false, message: 'fetch failed' })).toBe('error');
  });
});

describe('settleSuccess', () => {
  it('records the item when this attempt still owns the receipt', async () => {
    const store = new ScriptedStore();
    expect(await settleSuccess(store, 'item-a')).toEqual({ outcome: 'done', recordedItemId: 'item-a' });
    expect(store.ops('finalize')).toEqual([{ op: 'finalize', arg: 'item-a' }]);
    expect(store.ops('deleteItem')).toEqual([]);
    expect(store.sleeps).toEqual([]);
  });

  it('fenced out → superseded: deletes its own duplicate item and logs it', async () => {
    const store = new ScriptedStore({ finalize: [FENCED_OUT] });
    expect(await settleSuccess(store, 'item-a')).toEqual({ outcome: 'superseded', removedItemId: 'item-a' });
    expect(store.ops('finalize')).toHaveLength(1);
    expect(store.ops('deleteItem')).toEqual([{ op: 'deleteItem', arg: 'item-a' }]);
    expect(store.logs.map((l) => l.message)).toContain('capture: superseded, removed duplicate item-a');
  });

  it('fenced out without an item id → superseded, nothing to delete, logged as an error', async () => {
    const store = new ScriptedStore({ finalize: [FENCED_OUT] });
    expect(await settleSuccess(store, null)).toEqual({ outcome: 'superseded', removedItemId: null });
    expect(store.ops('deleteItem')).toEqual([]);
    expect(store.logs.some((l) => l.level === 'error')).toBe(true);
  });

  it('retries transient errors and thrown exceptions with backoff', async () => {
    const store = new ScriptedStore({ finalize: [TRANSIENT, new Error('network'), OWNED] });
    expect(await settleSuccess(store, 'item-a')).toEqual({ outcome: 'done', recordedItemId: 'item-a' });
    expect(store.ops('finalize')).toHaveLength(3);
    expect(store.sleeps).toEqual([SETTLE_BACKOFF_MS, SETTLE_BACKOFF_MS * 2]);
  });

  it('records the capture without the item when the item was already deleted (23503)', async () => {
    const store = new ScriptedStore({ finalize: [{ ok: false, code: '23503', message: 'fk' }, OWNED] });
    expect(await settleSuccess(store, 'item-a')).toEqual({ outcome: 'done', recordedItemId: null });
    expect(store.ops('finalize').map((c) => c.arg)).toEqual(['item-a', null]);
    expect(store.sleeps).toEqual([]);
  });

  it('gives up after SETTLE_ATTEMPTS as unrecorded — never deleting the (only) item', async () => {
    const store = new ScriptedStore({ finalize: [TRANSIENT] });
    expect(await settleSuccess(store, 'item-a')).toEqual({ outcome: 'unrecorded' });
    expect(store.ops('finalize')).toHaveLength(SETTLE_ATTEMPTS);
    expect(store.ops('deleteItem')).toEqual([]);
    expect(store.logs.filter((l) => l.message === 'capture: finalizing the receipt failed')).toHaveLength(SETTLE_ATTEMPTS);
  });

  it('retries removing the duplicate, and reports null when it never succeeds', async () => {
    const retried = new ScriptedStore({ finalize: [FENCED_OUT], deleteItem: [TRANSIENT, TRANSIENT, OWNED] });
    expect(await settleSuccess(retried, 'item-a')).toEqual({ outcome: 'superseded', removedItemId: 'item-a' });
    expect(retried.sleeps).toEqual([SETTLE_BACKOFF_MS, SETTLE_BACKOFF_MS * 2]);

    const stuck = new ScriptedStore({ finalize: [FENCED_OUT], deleteItem: [TRANSIENT] });
    expect(await settleSuccess(stuck, 'item-a')).toEqual({ outcome: 'superseded', removedItemId: null });
    expect(stuck.ops('deleteItem')).toHaveLength(SETTLE_ATTEMPTS);
  });
});

describe('settleFailure', () => {
  it('releases the receipt (no upload to consider)', async () => {
    const store = new ScriptedStore();
    expect(await settleFailure(store)).toEqual({ receipt: 'released', upload: 'none' });
    expect(store.calls.map((c) => c.op)).toEqual(['release']);
  });

  it('retries a failing release with backoff and logs each failure', async () => {
    const store = new ScriptedStore({ release: [TRANSIENT, new Error('network'), OWNED] });
    expect(await settleFailure(store)).toEqual({ receipt: 'released', upload: 'none' });
    expect(store.ops('release')).toHaveLength(3);
    expect(store.sleeps).toEqual([SETTLE_BACKOFF_MS, SETTLE_BACKOFF_MS * 2]);
    expect(store.logs.filter((l) => l.message === 'capture: releasing the receipt failed')).toHaveLength(2);
  });

  it('reports failed (logged as an error) when every release attempt fails', async () => {
    const store = new ScriptedStore({ release: [TRANSIENT] });
    expect(await settleFailure(store)).toEqual({ receipt: 'failed', upload: 'none' });
    expect(store.ops('release')).toHaveLength(SETTLE_ATTEMPTS);
    expect(store.logs.at(-1)).toMatchObject({ level: 'error', message: 'capture: releasing the receipt failed' });
  });

  it('does not retry a fenced-out release — the receipt belongs to someone else', async () => {
    const store = new ScriptedStore({ release: [FENCED_OUT] });
    expect(await settleFailure(store)).toEqual({ receipt: 'notOwned', upload: 'none' });
    expect(store.ops('release')).toHaveLength(1);
    expect(store.sleeps).toEqual([]);
  });

  it('removes its one-shot upload only after a fenced touch proves ownership, then releases', async () => {
    const store = new ScriptedStore();
    expect(await settleFailure(store, 'uid/cid.jpg')).toEqual({ receipt: 'released', upload: 'removed' });
    expect(store.calls).toEqual([{ op: 'touch' }, { op: 'removeObject', arg: 'uid/cid.jpg' }, { op: 'release' }]);
  });

  it('superseded → keeps the shared upload and leaves the receipt alone', async () => {
    const store = new ScriptedStore({ touch: [FENCED_OUT] });
    expect(await settleFailure(store, 'uid/cid.jpg')).toEqual({ receipt: 'untouched', upload: 'kept' });
    expect(store.calls.map((c) => c.op)).toEqual(['touch']);
  });

  it('keeps the upload when ownership cannot be confirmed or removal fails, and still releases', async () => {
    const unsure = new ScriptedStore({ touch: [TRANSIENT] });
    expect(await settleFailure(unsure, 'uid/cid.jpg')).toEqual({ receipt: 'released', upload: 'kept' });
    expect(unsure.ops('removeObject')).toEqual([]);

    const stuck = new ScriptedStore({ removeObject: [TRANSIENT] });
    expect(await settleFailure(stuck, 'uid/cid.jpg')).toEqual({ receipt: 'released', upload: 'kept' });
  });
});

/**
 * In-memory receipt with the same fence the handler's SQL applies: finalize
 * matches on attempt_id only; touch/release also require status 'pending'.
 */
class FencedReceipt {
  row: { status: 'pending' | 'done'; attempt_id: string; item_id: string | null } | null = null;
  items = new Set<string>();
  objects = new Set<string>();
  reserve(attemptId: string) { this.row = { status: 'pending', attempt_id: attemptId, item_id: null }; }
  takeOver(attemptId: string) { if (this.row?.status === 'pending') this.row = { ...this.row, attempt_id: attemptId }; }
  storeFor(attemptId: string): AttemptStore {
    const mine = () => this.row !== null && this.row.attempt_id === attemptId;
    const minePending = () => mine() && this.row!.status === 'pending';
    return {
      finalize: async (itemId) => {
        if (!mine()) return FENCED_OUT;
        this.row = { ...this.row!, status: 'done', item_id: itemId };
        return OWNED;
      },
      release: async () => {
        if (!minePending()) return FENCED_OUT;
        this.row = null;
        return OWNED;
      },
      touch: async () => (minePending() ? OWNED : FENCED_OUT),
      deleteItem: async (itemId) => ({ ok: true, rows: this.items.delete(itemId) ? 1 : 0 }),
      removeObject: async (path) => ({ ok: true, rows: this.objects.delete(path) ? 1 : 0 }),
      sleep: async () => {},
      log: () => {},
    };
  }
}

describe('fencing scenarios: a zombie attempt vs its successor', () => {
  it('the zombie finishes after a takeover: it removes its duplicate and the successor wins', async () => {
    const receipt = new FencedReceipt();
    receipt.reserve('A');
    receipt.takeOver('B'); // A stalled ≥ 120 s
    receipt.items.add('item-a');
    expect(await settleSuccess(receipt.storeFor('A'), 'item-a')).toEqual({ outcome: 'superseded', removedItemId: 'item-a' });
    receipt.items.add('item-b');
    expect(await settleSuccess(receipt.storeFor('B'), 'item-b')).toEqual({ outcome: 'done', recordedItemId: 'item-b' });
    expect(receipt.row).toEqual({ status: 'done', attempt_id: 'B', item_id: 'item-b' });
    expect([...receipt.items]).toEqual(['item-b']);
  });

  it('the zombie finishes after the successor is done: the done row is untouched', async () => {
    const receipt = new FencedReceipt();
    receipt.reserve('A');
    receipt.takeOver('B');
    receipt.items.add('item-b');
    await settleSuccess(receipt.storeFor('B'), 'item-b');
    receipt.items.add('item-a');
    expect((await settleSuccess(receipt.storeFor('A'), 'item-a')).outcome).toBe('superseded');
    expect(receipt.row).toEqual({ status: 'done', attempt_id: 'B', item_id: 'item-b' });
    expect([...receipt.items]).toEqual(['item-b']);
  });

  it('the zombie fails after a takeover: it neither deletes the live receipt nor the shared upload', async () => {
    const receipt = new FencedReceipt();
    receipt.reserve('A');
    receipt.objects.add('uid/cid.jpg');
    receipt.takeOver('B');
    expect(await settleFailure(receipt.storeFor('A'), 'uid/cid.jpg')).toEqual({ receipt: 'untouched', upload: 'kept' });
    expect(receipt.row).toEqual({ status: 'pending', attempt_id: 'B', item_id: null });
    expect(receipt.objects.has('uid/cid.jpg')).toBe(true);
    expect(await settleFailure(receipt.storeFor('A'))).toEqual({ receipt: 'notOwned', upload: 'none' });
    expect(receipt.row?.attempt_id).toBe('B');
  });

  it('the successor released after failing, then the zombie finishes: its item goes, so the retry starts clean', async () => {
    const receipt = new FencedReceipt();
    receipt.reserve('A');
    receipt.takeOver('B');
    await settleFailure(receipt.storeFor('B'));
    expect(receipt.row).toBeNull();
    receipt.items.add('item-a');
    expect(await settleSuccess(receipt.storeFor('A'), 'item-a')).toEqual({ outcome: 'superseded', removedItemId: 'item-a' });
    expect(receipt.items.size).toBe(0);
  });

  it("an attempt's own retried finalize stays owned (no status filter) — it never deletes its only item", async () => {
    const receipt = new FencedReceipt();
    receipt.reserve('A');
    receipt.items.add('item-a');
    const store = receipt.storeFor('A');
    await store.finalize('item-a'); // committed, but the response was lost
    expect(await settleSuccess(store, 'item-a')).toEqual({ outcome: 'done', recordedItemId: 'item-a' });
    expect([...receipt.items]).toEqual(['item-a']);
  });
});

describe('afterDraining', () => {
  const bodyOf = (chunks: number, size = 1024) => {
    let sent = 0;
    return new ReadableStream<Uint8Array>({
      pull(controller) {
        if (sent++ >= chunks) return controller.close();
        controller.enqueue(new Uint8Array(size));
      },
    });
  };

  it('reads the body before answering, so the gateway can deliver the response', async () => {
    const req = new Request('https://x.test/', { method: 'POST', body: bodyOf(64), duplex: 'half' } as RequestInit);
    const res = await afterDraining(req, new Response('{"error":"subscription_required"}', { status: 403 }));
    expect(req.bodyUsed).toBe(true);
    expect(res.status).toBe(403);
    expect(await res.text()).toBe('{"error":"subscription_required"}');
  });

  it('passes the response through untouched when the body was already read', async () => {
    const req = new Request('https://x.test/', { method: 'POST', body: 'hi', duplex: 'half' } as RequestInit);
    await req.text();
    const res = await afterDraining(req, new Response('ok', { status: 401 }));
    expect(res.status).toBe(401);
    expect(await res.text()).toBe('ok');
  });

  it('survives a request with no body at all', async () => {
    const req = new Request('https://x.test/', { method: 'GET' });
    const res = await afterDraining(req, new Response(null, { status: 405 }));
    expect(res.status).toBe(405);
  });
});
