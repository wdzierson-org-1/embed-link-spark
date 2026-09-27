// @vitest-environment node
import { describe, expect, it } from 'vitest';
import {
  MULTIPART_BODY_LIMIT,
  ONE_SHOT_FILE_LIMIT,
  RECEIPT_HEARTBEAT_MS,
  RECEIPT_TAKEOVER_MS,
  decideReceipt,
  downstreamBodyFor,
  downstreamPathFor,
  exceedsMultipartBodyLimit,
  fileExtensionFor,
  normalizeDownstreamItem,
  parseCaptureMeta,
  requestBodyKind,
  storedObjectPath,
  type CaptureMeta,
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
});
