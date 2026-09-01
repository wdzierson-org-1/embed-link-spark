import { resolveSessionTarget, bucketConversations, SESSION_GAP_MS } from './chatSessions';

const NOW = new Date('2026-08-27T15:00:00Z');
const iso = (msAgo: number) => new Date(NOW.getTime() - msAgo).toISOString();
const row = (id: string, msAgo: number) => ({
  id, title: id, last_message_at: iso(msAgo), message_count: 2, preview: null,
});

describe('resolveSessionTarget', () => {
  it('starts new with no prior conversation', () => {
    expect(resolveSessionTarget(null, NOW)).toEqual({ kind: 'new' });
  });

  it('continues within the gap', () => {
    expect(
      resolveSessionTarget({ id: 'c1', title: 'T', last_message_at: iso(SESSION_GAP_MS - 60_000) }, NOW)
    ).toEqual({ kind: 'continue', id: 'c1', title: 'T' });
  });

  it('starts new at exactly the gap boundary', () => {
    expect(
      resolveSessionTarget({ id: 'c1', title: 'T', last_message_at: iso(SESSION_GAP_MS) }, NOW)
    ).toEqual({ kind: 'new' });
  });

  it('starts new when last_message_at is null', () => {
    expect(
      resolveSessionTarget({ id: 'c1', title: 'T', last_message_at: null }, NOW)
    ).toEqual({ kind: 'new' });
  });
});

describe('bucketConversations', () => {
  it('buckets Today / Yesterday / This week / month / older year', () => {
    const rows = [
      row('today', 60 * 60 * 1000),                 // Thu Aug 27
      row('yesterday', 26 * 60 * 60 * 1000),        // Wed Aug 26
      row('thisweek', 3 * 24 * 60 * 60 * 1000),     // Mon Aug 24 (same ISO week)
      row('july', 40 * 24 * 60 * 60 * 1000),        // Jul 18
      row('lastyear', 400 * 24 * 60 * 60 * 1000),   // Jul 2025
    ];
    const buckets = bucketConversations(rows, NOW);
    expect(buckets.map(b => b.label)).toEqual(['Today', 'Yesterday', 'This week', 'July', 'July 2025']);
    expect(buckets[0].rows[0].id).toBe('today');
  });

  it('groups multiple rows under one bucket, preserving order', () => {
    const rows = [row('a', 1000), row('b', 2000)];
    const buckets = bucketConversations(rows, NOW);
    expect(buckets).toHaveLength(1);
    expect(buckets[0].rows.map(r => r.id)).toEqual(['a', 'b']);
  });

  it('returns empty for no rows', () => {
    expect(bucketConversations([], NOW)).toEqual([]);
  });
});
