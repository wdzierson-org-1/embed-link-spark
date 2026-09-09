// Pure helpers for the temporary admin dashboard
// (spec: docs/superpowers/specs/2026-09-08-admin-dashboard-design.md).
// One row per auth user, as returned by the admin_user_stats() RPC through
// the admin-stats edge function.

export interface AdminUserRow {
  user_id: string;
  email: string | null;
  username: string | null;
  display_name: string | null;
  is_anonymous: boolean;
  created_at: string;
  last_sign_in_at: string | null;
  /** Explicit sign-ins (auth audit log `login` entries). */
  total_logins: number;
  /** Distinct UTC days with a sign-in or a token refresh. */
  active_days: number;
  last_active_at: string | null;
  item_count: number;
  items_last_7d: number;
  last_item_at: string | null;
  items_by_type: Record<string, number>;
}

export type SortDir = 'asc' | 'desc';
export type SortKey =
  | 'name'
  | 'email'
  | 'created_at'
  | 'last_sign_in_at'
  | 'last_active_at'
  | 'total_logins'
  | 'per_day'
  | 'active_days'
  | 'item_count'
  | 'last_item_at';

const DAY_MS = 24 * 60 * 60 * 1000;
const WEEK_MS = 7 * DAY_MS;

/** Whole days since `iso`, never less than one (a same-day signup is one day). */
export const daysSince = (iso: string, now: Date): number =>
  Math.max(1, Math.floor((now.getTime() - new Date(iso).getTime()) / DAY_MS));

export const loginsPerDay = (row: AdminUserRow, now: Date): number =>
  row.total_logins / daysSince(row.created_at, now);

/** Logins per day for the table: coarser as it grows, a bare 0 for none. */
export const formatRate = (rate: number): string => {
  if (rate === 0) return '0';
  if (rate >= 10) return rate.toFixed(0);
  if (rate >= 1) return rate.toFixed(1);
  return rate.toFixed(2);
};

/** Will's plus-addressed fixtures (`will+uitest@…`), on whichever domain. */
export const isTestAccount = (email: string | null): boolean => !!email && /^will\+/i.test(email);

export const memberName = (row: AdminUserRow): string =>
  row.display_name?.trim() || row.username?.trim() || row.email?.split('@')[0] || 'Anonymous';

const TYPE_LABELS: Record<string, [string, string]> = {
  link: ['link', 'links'],
  text: ['note', 'notes'],
  image: ['image', 'images'],
  audio: ['audio', 'audio'],
  video: ['video', 'videos'],
  document: ['document', 'documents'],
  collection: ['collection', 'collections'],
};

export const typeLabel = (type: string, count: number): string => {
  const [one, many] = TYPE_LABELS[type] ?? [type, type];
  return count === 1 ? one : many;
};

/** "12 links, 3 notes, 1 image" — largest first; past `limit` types, "+N more". */
export const describeTypes = (byType: Record<string, number>, limit = Infinity): string => {
  const entries = Object.entries(byType)
    .filter(([, n]) => n > 0)
    .sort((a, b) => b[1] - a[1]);
  const shown = entries
    .slice(0, limit)
    .map(([type, n]) => `${n} ${typeLabel(type, n)}`)
    .join(', ');
  const rest = entries.length - Math.min(entries.length, limit);
  return rest > 0 ? `${shown} +${rest} more` : shown;
};

/** Compact relative time for dense tables: "45m ago", "3mo ago", "Never". */
export const compactAgo = (iso: string | null, now: Date): string => {
  if (!iso) return 'Never';
  const seconds = Math.max(0, Math.floor((now.getTime() - new Date(iso).getTime()) / 1000));
  if (seconds < 60) return 'just now';
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (days < 30) return `${days}d ago`;
  if (days < 365) return `${Math.floor(days / 30)}mo ago`;
  return `${Math.floor(days / 365)}y ago`;
};

export interface MemberSummary {
  members: number;
  anonymous: number;
  activeLast7d: number;
  items: number;
  itemsLast7d: number;
}

export const summarizeMembers = (rows: AdminUserRow[], now: Date): MemberSummary => {
  const cutoff = now.getTime() - WEEK_MS;
  const summary: MemberSummary = { members: 0, anonymous: 0, activeLast7d: 0, items: 0, itemsLast7d: 0 };
  for (const row of rows) {
    summary.items += row.item_count;
    summary.itemsLast7d += row.items_last_7d;
    if (row.is_anonymous) {
      summary.anonymous += 1;
      continue;
    }
    summary.members += 1;
    if (row.last_active_at && new Date(row.last_active_at).getTime() >= cutoff) summary.activeLast7d += 1;
  }
  return summary;
};

export const filterRows = (
  rows: AdminUserRow[],
  { query, hideTestAccounts }: { query: string; hideTestAccounts: boolean }
): AdminUserRow[] => {
  const q = query.trim().toLowerCase();
  return rows.filter((row) => {
    if (row.is_anonymous) return false;
    if (hideTestAccounts && isTestAccount(row.email)) return false;
    if (!q) return true;
    return [row.display_name, row.username, row.email].some((v) => v?.toLowerCase().includes(q));
  });
};

const time = (iso: string | null): number | null => (iso ? new Date(iso).getTime() : null);

// Missing values sort last whichever way the column is sorted — "never
// active" belongs at the bottom, not at the top of an ascending sort.
const compareNullable = (a: number | null, b: number | null, dir: SortDir): number => {
  if (a === null && b === null) return 0;
  if (a === null) return 1;
  if (b === null) return -1;
  return dir === 'asc' ? a - b : b - a;
};

export const sortRows = (rows: AdminUserRow[], key: SortKey, dir: SortDir, now: Date): AdminUserRow[] => {
  const value = (row: AdminUserRow): number | string | null => {
    switch (key) {
      case 'name':
        return memberName(row).toLowerCase();
      case 'email':
        return (row.email ?? '').toLowerCase();
      case 'created_at':
        return time(row.created_at);
      case 'last_sign_in_at':
        return time(row.last_sign_in_at);
      case 'last_active_at':
        return time(row.last_active_at);
      case 'last_item_at':
        return time(row.last_item_at);
      case 'total_logins':
        return row.total_logins;
      case 'active_days':
        return row.active_days;
      case 'item_count':
        return row.item_count;
      case 'per_day':
        return loginsPerDay(row, now);
    }
  };
  return [...rows].sort((a, b) => {
    const va = value(a);
    const vb = value(b);
    if (typeof va === 'string' || typeof vb === 'string') {
      const cmp = String(va ?? '').localeCompare(String(vb ?? ''));
      return dir === 'asc' ? cmp : -cmp;
    }
    return compareNullable(va, vb, dir);
  });
};
