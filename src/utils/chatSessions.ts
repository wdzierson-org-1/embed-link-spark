import { differenceInCalendarDays, format, isSameWeek } from 'date-fns';

// A conversation is a burst of activity: 3+ hours of silence starts a new one.
export const SESSION_GAP_MS = 3 * 60 * 60 * 1000;

export interface SessionCandidate {
  id: string;
  title: string | null;
  last_message_at: string | null;
}

export function resolveSessionTarget(
  latest: SessionCandidate | null,
  now: Date
): { kind: 'continue'; id: string; title: string | null } | { kind: 'new' } {
  if (!latest?.last_message_at) return { kind: 'new' };
  const elapsed = now.getTime() - new Date(latest.last_message_at).getTime();
  return elapsed < SESSION_GAP_MS
    ? { kind: 'continue', id: latest.id, title: latest.title }
    : { kind: 'new' };
}

export interface ConversationListRow {
  id: string;
  title: string | null;
  last_message_at: string;
  message_count: number;
  preview: string | null;
}

export interface ConversationBucket {
  label: string;
  rows: ConversationListRow[];
}

// Rows arrive newest-first (list_conversations orders by last_message_at desc),
// so buckets emit in display order with one pass.
export function bucketConversations(
  rows: ConversationListRow[],
  now: Date
): ConversationBucket[] {
  const buckets: ConversationBucket[] = [];
  for (const r of rows) {
    const d = new Date(r.last_message_at);
    const days = differenceInCalendarDays(now, d);
    let label: string;
    if (days <= 0) label = 'Today';
    else if (days === 1) label = 'Yesterday';
    else if (isSameWeek(d, now, { weekStartsOn: 1 })) label = 'This week';
    else label = d.getFullYear() === now.getFullYear() ? format(d, 'MMMM') : format(d, 'MMMM yyyy');
    const last = buckets[buckets.length - 1];
    if (last && last.label === label) last.rows.push(r);
    else buckets.push({ label, rows: [r] });
  }
  return buckets;
}
