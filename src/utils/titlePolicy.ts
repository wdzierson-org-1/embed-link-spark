// Title policy for uploaded media and documents (ui-changes.md 2026-08-26).
//
// Titles are AI-derived; the original filename is metadata and lives in
// attributes.media.file_name. A title that is still a filename (or empty) is a
// placeholder the enrichment pipeline may replace; anything else is the user's
// and is never touched.
//
// PAIRED FILE: supabase/functions/_shared/titlePolicy.ts is the Deno copy of
// these pure helpers for the edge functions. Any change here must be made
// there too (and vice versa) — tests live in titlePolicy.test.ts beside this
// file.

// Token the transcript-title prompt returns instead of a title when the
// content is too personal to surface as a library card title.
export const KEEP_FILENAME_TOKEN = 'KEEP_FILENAME';

// Storage object names our clients generate (`${Date.now()}.ext`) carry no
// meaning — they get replaced but are never worth preserving as file_name.
export const isStorageTimestampName = (name: string): boolean =>
  /^\d{10,17}\.[a-z0-9]+$/i.test(name.trim());

// UUID object names (iOS share extension, Voice Memos shares:
// `72322570-a4bc-4515-935c-ff384090f068.m4a`) — same deal: replaceable,
// not worth preserving.
export const isUuidObjectName = (name: string): boolean =>
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.[a-z0-9]+$/i.test(name.trim());

export const fileBasename = (path: string | null | undefined): string | null =>
  path?.split('/').pop() ?? null;

// Filename-shaped: ends in an extension (dot + 2-5 chars starting with a
// letter: .m4a .docx .jpeg …), plus the digit-leading container formats.
// Deliberately does NOT match version suffixes like "Meeting notes v2.1".
const EXT_SUFFIX_RE = /\.([a-z][a-z0-9]{1,4}|3gp2?|3g2|7z)$/i;

export const isPlaceholderTitle = (
  title: string | null | undefined,
  filePath: string | null | undefined,
): boolean => {
  const t = (title ?? '').trim();
  if (!t) return true;
  const base = fileBasename(filePath);
  if (base && t === base) return true;
  if (isStorageTimestampName(t) || isUuidObjectName(t)) return true;
  return EXT_SUFFIX_RE.test(t);
};

export const capTitle = (title: string): string => {
  const t = title.trim().replace(/^["']|["']$/g, '');
  return t.length > 90 ? `${t.slice(0, 90).trimEnd()}…` : t;
};
