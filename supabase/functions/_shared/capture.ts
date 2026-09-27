// supabase/functions/_shared/capture.ts
//
// Pure logic for the idempotent `capture` endpoint (supabase/functions/capture;
// contract: docs/PLATFORM_API.md → "POST /capture"). Import-free so it runs
// under Deno and vitest — the handler owns every network and database call.
//
// capture wraps the existing add-note / add-url / add-file endpoints: the
// client sends a client-generated `capture_id`, the handler reserves a
// `capture_receipts` row for it, and a retry of the same id — from any
// process, at any time — returns the item the first attempt created instead
// of creating a second one.

export type CaptureKind = 'note' | 'url' | 'file';

const CAPTURE_KINDS: ReadonlySet<string> = new Set(['note', 'url', 'file']);

/** Largest file accepted by a one-shot multipart request (iOS `CaptureAPI.oneShotFileLimit`). */
export const ONE_SHOT_FILE_LIMIT = 45 * 1024 * 1024;

/**
 * Room for the `meta` part and the multipart boundaries on top of a file at the
 * one-shot limit, so every file the client is allowed to send one-shot fits
 * under the Content-Length guard.
 */
export const MULTIPART_ENVELOPE_ALLOWANCE = 1024 * 1024;

/** A multipart request whose Content-Length exceeds this gets 413 before the body is read. */
export const MULTIPART_BODY_LIMIT = ONE_SHOT_FILE_LIMIT + MULTIPART_ENVELOPE_ALLOWANCE;

/** A pending receipt younger than this belongs to a live attempt (409); an older one may be taken over. */
export const RECEIPT_TAKEOVER_MS = 120_000;

/**
 * A live attempt re-stamps its pending receipt this often, so a slow downstream
 * call is never mistaken for a dead attempt and taken over (which could create
 * a second item).
 */
export const RECEIPT_HEARTBEAT_MS = 30_000;

export interface CaptureMeta {
  /** Lowercase UUID — the idempotency key. */
  capture_id: string;
  kind: CaptureKind;
  content?: string;
  title?: string;
  url?: string;
  is_public: boolean;
  /** Only ever a non-empty plain object; `{}` is dropped. */
  attributes?: Record<string, unknown>;
  remind_at?: string;
  /** Trimmed + lowercased. Required for kind=file. */
  mime_type?: string;
  file_name?: string;
  file_size?: number;
  /** Two-step files only: an object the client already uploaded, inside `<uid>/`. */
  file_path?: string;
}

export interface ParseContext {
  /** The authenticated caller; `file_path` must live in this user's folder. */
  userId: string;
  /** True when the request carried a multipart `file` part. */
  hasFile: boolean;
}

export type ParseResult =
  | { ok: true; meta: CaptureMeta; warnings: string[] }
  | { ok: false; error: string };

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MIME_RE = /^[a-z0-9!#$&^_.+-]+\/[a-z0-9!#$&^_.+-]+(\s*;.*)?$/;

const isPlainObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

/** `undefined` and `null` both mean "not sent". */
const isAbsent = (value: unknown): value is null | undefined => value === undefined || value === null;

/**
 * Validate a capture request's meta object. Structural problems (missing or
 * malformed id/kind, missing required content, a file_path outside the
 * caller's folder, …) fail with a message for a 400. Metadata problems never
 * fail a capture: invalid `attributes`, `remind_at`, or `file_size` are dropped
 * and reported in `warnings` (same rule as the add-* endpoints).
 */
export function parseCaptureMeta(raw: unknown, ctx: ParseContext): ParseResult {
  if (!isPlainObject(raw)) return { ok: false, error: 'meta must be a JSON object' };
  const warnings: string[] = [];

  const captureId = raw.capture_id;
  if (isAbsent(captureId) || captureId === '') return { ok: false, error: 'capture_id is required' };
  if (typeof captureId !== 'string' || !UUID_RE.test(captureId)) {
    return { ok: false, error: 'capture_id must be a UUID' };
  }

  const kind = raw.kind;
  if (isAbsent(kind) || kind === '') return { ok: false, error: 'kind is required' };
  if (typeof kind !== 'string' || !CAPTURE_KINDS.has(kind)) {
    return { ok: false, error: 'kind must be one of note, url, file' };
  }

  const strings: Record<string, string | undefined> = {};
  for (const key of ['content', 'title', 'url', 'mime_type', 'file_name', 'file_path'] as const) {
    const value = raw[key];
    if (isAbsent(value)) continue;
    if (typeof value !== 'string') return { ok: false, error: `${key} must be a string` };
    strings[key] = value;
  }

  let isPublic = false;
  if (!isAbsent(raw.is_public)) {
    if (typeof raw.is_public !== 'boolean') return { ok: false, error: 'is_public must be a boolean' };
    isPublic = raw.is_public;
  }

  const meta: CaptureMeta = {
    capture_id: captureId.toLowerCase(),
    kind: kind as CaptureKind,
    is_public: isPublic,
  };
  if (strings.content !== undefined) meta.content = strings.content;
  if (strings.title !== undefined) meta.title = strings.title;

  // Metadata: dropped with a warning, never a 4xx.
  const attributes = raw.attributes;
  if (isPlainObject(attributes)) {
    if (Object.keys(attributes).length > 0) meta.attributes = attributes;
  } else if (!isAbsent(attributes)) {
    warnings.push('attributes ignored: not a JSON object');
  }
  if (typeof raw.remind_at === 'string') {
    meta.remind_at = raw.remind_at;
  } else if (!isAbsent(raw.remind_at)) {
    warnings.push('remind_at ignored: not a string');
  }

  if (ctx.hasFile && meta.kind !== 'file') {
    return { ok: false, error: 'a file part is only accepted with kind "file"' };
  }

  switch (meta.kind) {
    case 'note': {
      if (!meta.content || meta.content.trim() === '') return { ok: false, error: 'content is required for a note' };
      break;
    }
    case 'url': {
      const url = strings.url;
      if (!url || url.trim() === '') return { ok: false, error: 'url is required for kind "url"' };
      try {
        new URL(url);
      } catch {
        return { ok: false, error: 'url is not a valid URL' };
      }
      meta.url = url;
      break;
    }
    case 'file': {
      const mime = strings.mime_type?.trim().toLowerCase();
      if (!mime) return { ok: false, error: 'mime_type is required for kind "file"' };
      if (!MIME_RE.test(mime)) return { ok: false, error: 'mime_type must look like type/subtype' };
      meta.mime_type = mime;
      if (strings.file_name !== undefined) meta.file_name = strings.file_name;

      const size = raw.file_size;
      if (typeof size === 'number' && Number.isSafeInteger(size) && size >= 0) {
        meta.file_size = size;
      } else if (!isAbsent(size)) {
        warnings.push('file_size ignored: not a non-negative integer');
      }

      const filePath = strings.file_path;
      if (ctx.hasFile) {
        if (filePath !== undefined) return { ok: false, error: 'send either a file part or file_path, not both' };
      } else {
        if (!filePath) return { ok: false, error: 'file_path is required when no file part is sent' };
        if (!filePath.startsWith(`${ctx.userId}/`)) {
          return { ok: false, error: 'file_path must be inside your own storage folder' };
        }
        if (filePath.split('/').some((segment) => segment === '' || segment === '.' || segment === '..')) {
          return { ok: false, error: 'file_path contains invalid segments' };
        }
        meta.file_path = filePath;
      }
      break;
    }
  }

  return { ok: true, meta, warnings };
}

const MIME_EXTENSIONS: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/jpg': 'jpg',
  'image/pjpeg': 'jpg',
  'image/png': 'png',
  'image/gif': 'gif',
  'image/webp': 'webp',
  'image/heic': 'heic',
  'image/heif': 'heif',
  'image/avif': 'avif',
  'image/tiff': 'tiff',
  'image/bmp': 'bmp',
  'image/svg+xml': 'svg',
  'video/mp4': 'mp4',
  'video/quicktime': 'mov',
  'video/x-m4v': 'm4v',
  'video/webm': 'webm',
  'video/mpeg': 'mpeg',
  'video/3gpp': '3gp',
  'audio/mp4': 'm4a',
  'audio/m4a': 'm4a',
  'audio/x-m4a': 'm4a',
  'audio/aac': 'aac',
  'audio/mpeg': 'mp3',
  'audio/mp3': 'mp3',
  'audio/wav': 'wav',
  'audio/x-wav': 'wav',
  'audio/wave': 'wav',
  'audio/webm': 'webm',
  'audio/ogg': 'ogg',
  'audio/flac': 'flac',
  'audio/x-caf': 'caf',
  'audio/amr': 'amr',
  'application/pdf': 'pdf',
  'application/msword': 'doc',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx',
  'application/vnd.ms-excel': 'xls',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
  'application/vnd.ms-powerpoint': 'ppt',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation': 'pptx',
  'application/rtf': 'rtf',
  'application/epub+zip': 'epub',
  'application/zip': 'zip',
  'application/json': 'json',
  'text/plain': 'txt',
  'text/markdown': 'md',
  'text/csv': 'csv',
  'text/html': 'html',
  'text/rtf': 'rtf',
};

const EXTENSION_RE = /^[a-z0-9]{1,10}$/;

/**
 * Storage extension for an uploaded file: the original file name's extension
 * when it has a sane one, else a MIME map, else `bin`. Always lowercase.
 */
export function fileExtensionFor(fileName: string | null | undefined, mimeType: string | null | undefined): string {
  if (fileName) {
    const base = fileName.split(/[\\/]/).pop() ?? '';
    const dot = base.lastIndexOf('.');
    if (dot > 0 && dot < base.length - 1) {
      const ext = base.slice(dot + 1).toLowerCase();
      if (EXTENSION_RE.test(ext)) return ext;
    }
  }
  if (mimeType) {
    const essence = mimeType.split(';')[0].trim().toLowerCase();
    const mapped = MIME_EXTENSIONS[essence];
    if (mapped) return mapped;
  }
  return 'bin';
}

/** Deterministic object path for a one-shot upload: `<uid>/<capture_id>.<ext>` (retries overwrite, never pile up). */
export const storedObjectPath = (userId: string, captureId: string, extension: string): string =>
  `${userId}/${captureId.toLowerCase()}.${extension}`;

export type DownstreamPath = 'add-note' | 'add-url' | 'add-file';

export function downstreamPathFor(kind: CaptureKind): DownstreamPath {
  switch (kind) {
    case 'note':
      return 'add-note';
    case 'url':
      return 'add-url';
    case 'file':
      return 'add-file';
  }
}

/**
 * The body the existing add-* endpoint expects, built from validated meta.
 * Keys whose value is undefined are omitted; `attributes` is only present
 * when non-empty. `storedPath` is where the handler put a multipart upload;
 * two-step captures use the meta's own `file_path`.
 */
export function downstreamBodyFor(meta: CaptureMeta, storedPath?: string): Record<string, unknown> {
  const body: Record<string, unknown> = {};
  const put = (key: string, value: unknown) => {
    if (value !== undefined) body[key] = value;
  };

  switch (meta.kind) {
    case 'url':
      put('url', meta.url);
      put('content', meta.content);
      break;
    case 'note':
      put('content', meta.content);
      put('title', meta.title);
      break;
    case 'file': {
      const filePath = storedPath ?? meta.file_path;
      if (!filePath) throw new Error('downstreamBodyFor: a file capture needs a stored path or file_path');
      put('file_path', filePath);
      put('mime_type', meta.mime_type);
      put('file_size', meta.file_size);
      put('content', meta.content);
      put('title', meta.title);
      break;
    }
  }
  body.is_public = meta.is_public;
  if (meta.attributes && Object.keys(meta.attributes).length > 0) body.attributes = meta.attributes;
  put('remind_at', meta.remind_at);
  return body;
}

export interface ReceiptRow {
  status: string;
  item_id: string | null;
  updated_at: string;
}

export type ReceiptDecision =
  | { action: 'proceed' }
  | { action: 'duplicate'; itemId: string | null }
  | { action: 'inProgress' }
  | { action: 'takeOver' };

/**
 * What to do when a receipt already exists for this capture_id:
 * none → proceed; done → duplicate (its item; null once the user deleted it);
 * pending and younger than RECEIPT_TAKEOVER_MS → inProgress (409);
 * pending and older (or an unreadable timestamp) → takeOver — that attempt
 * died without finishing or releasing its receipt.
 */
export function decideReceipt(existing: ReceiptRow | null | undefined, now: number | Date): ReceiptDecision {
  if (!existing) return { action: 'proceed' };
  if (existing.status === 'done') return { action: 'duplicate', itemId: existing.item_id ?? null };
  const nowMs = typeof now === 'number' ? now : now.getTime();
  const updatedMs = Date.parse(existing.updated_at);
  if (!Number.isFinite(updatedMs)) return { action: 'takeOver' };
  return nowMs - updatedMs < RECEIPT_TAKEOVER_MS ? { action: 'inProgress' } : { action: 'takeOver' };
}

/** add-url / add-file answer `{ success, item }`; add-note answers `{ success, note }`. */
export function normalizeDownstreamItem(body: unknown): Record<string, unknown> | null {
  if (!isPlainObject(body)) return null;
  const item = body.item ?? body.note ?? null;
  return isPlainObject(item) ? item : null;
}

export type RequestBodyKind = 'json' | 'multipart';

/** JSON (also when no Content-Type is sent) or multipart; null for anything else. */
export function requestBodyKind(contentType: string | null | undefined): RequestBodyKind | null {
  const essence = (contentType ?? '').split(';')[0].trim().toLowerCase();
  if (essence === '' || essence === 'application/json') return 'json';
  if (essence === 'multipart/form-data') return 'multipart';
  return null;
}

/** True when a declared Content-Length is over the multipart limit; unknown lengths pass (the file part is re-checked after parsing). */
export function exceedsMultipartBodyLimit(contentLength: string | null | undefined, limit = MULTIPART_BODY_LIMIT): boolean {
  if (!contentLength || !/^\d+$/.test(contentLength.trim())) return false;
  return Number(contentLength.trim()) > limit;
}
