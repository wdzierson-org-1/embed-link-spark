// Request parsing + the item column list for the temporary admin dashboard
// (spec: docs/superpowers/specs/2026-09-08-admin-dashboard-design.md).
// Plain TS with no Deno imports so vitest can check it against the web app's
// useItems column list.

// The member page recreates the library grid, so it loads exactly what the
// grid loads (src/hooks/useItems.ts ITEM_LIST_COLUMN_NAMES) plus the owner.
export const ADMIN_ITEM_COLUMNS = [
  'id',
  'type',
  'title',
  'content',
  'url',
  'file_path',
  'description',
  'summary',
  'created_at',
  'mime_type',
  'file_size',
  'is_public',
  'supplemental_note',
  'attributes',
  'remind_at',
  'reminder_cleared_at',
  'user_id',
];

export type AdminRequest =
  | { action: 'users' }
  | { action: 'items'; userId: string }
  | { error: string };

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function parseAdminRequest(body: unknown): AdminRequest {
  if (!body || typeof body !== 'object') return { error: 'unknown action' };
  const { action, user_id: userId } = body as { action?: unknown; user_id?: unknown };
  if (action === 'users') return { action: 'users' };
  if (action === 'items') {
    if (typeof userId !== 'string' || !UUID_RE.test(userId)) return { error: 'user_id must be a uuid' };
    return { action: 'items', userId };
  }
  return { error: 'unknown action' };
}
