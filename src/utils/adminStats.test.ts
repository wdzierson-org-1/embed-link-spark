import { describe, expect, it } from 'vitest';
import {
  describeTypes,
  filterRows,
  isTestAccount,
  loginsPerDay,
  memberName,
  sortRows,
  summarizeMembers,
  type AdminUserRow,
} from './adminStats';

const now = new Date('2026-09-08T12:00:00Z');

const row = (over: Partial<AdminUserRow> = {}): AdminUserRow => ({
  user_id: 'u',
  email: 'a@example.com',
  username: 'a',
  display_name: null,
  is_anonymous: false,
  created_at: '2026-08-29T12:00:00Z',
  last_sign_in_at: null,
  total_logins: 0,
  active_days: 0,
  last_active_at: null,
  item_count: 0,
  items_last_7d: 0,
  last_item_at: null,
  items_by_type: {},
  ...over,
});

describe('loginsPerDay', () => {
  it('divides logins by whole days since signup', () => {
    expect(loginsPerDay(row({ total_logins: 20 }), now)).toBe(2);
  });

  it('treats a same-day signup as one day', () => {
    expect(loginsPerDay(row({ total_logins: 3, created_at: '2026-09-08T09:00:00Z' }), now)).toBe(3);
  });
});

describe('isTestAccount', () => {
  it('flags plus-addressed will+ fixtures on any domain', () => {
    expect(isTestAccount('will+uitest@dzierson.com')).toBe(true);
    expect(isTestAccount('Will+test1@noodleai.app')).toBe(true);
  });

  it('keeps real members and the founder account', () => {
    expect(isTestAccount('will@dzierson.com')).toBe(false);
    expect(isTestAccount('rachel@gmail.com')).toBe(false);
    expect(isTestAccount(null)).toBe(false);
  });
});

describe('memberName', () => {
  it('prefers display name, then username, then the email local part', () => {
    expect(memberName(row({ display_name: 'Rachel H', username: 'rachel' }))).toBe('Rachel H');
    expect(memberName(row({ username: 'rachel' }))).toBe('rachel');
    expect(memberName(row({ username: null, email: 'someone@x.com' }))).toBe('someone');
  });

  it('names anonymous sessions honestly', () => {
    expect(memberName(row({ username: null, email: null, is_anonymous: true }))).toBe('Anonymous');
  });
});

describe('describeTypes', () => {
  it('lists types by count, largest first, with plural labels', () => {
    expect(describeTypes({ text: 3, link: 12, image: 1 })).toBe('12 links, 3 notes, 1 image');
  });

  it('is empty when nothing is saved', () => {
    expect(describeTypes({})).toBe('');
  });
});

describe('summarizeMembers', () => {
  it('counts members, anonymous sessions, weekly actives and items', () => {
    const rows = [
      row({ user_id: '1', last_active_at: '2026-09-07T00:00:00Z', item_count: 5, items_last_7d: 2 }),
      row({ user_id: '2', last_active_at: '2026-08-01T00:00:00Z', item_count: 1, items_last_7d: 0 }),
      row({ user_id: '3', is_anonymous: true, email: null, item_count: 1, items_last_7d: 1 }),
    ];
    expect(summarizeMembers(rows, now)).toEqual({
      members: 2,
      anonymous: 1,
      activeLast7d: 1,
      items: 7,
      itemsLast7d: 3,
    });
  });
});

describe('filterRows', () => {
  const rows = [
    row({ user_id: '1', email: 'rachel@gmail.com', username: 'rachel', display_name: 'Rachel' }),
    row({ user_id: '2', email: 'will+uitest@dzierson.com', username: 'uitest' }),
    row({ user_id: '3', email: null, username: null, is_anonymous: true }),
  ];

  it('never lists anonymous sessions and hides test accounts by default', () => {
    expect(filterRows(rows, { query: '', hideTestAccounts: true }).map((r) => r.user_id)).toEqual(['1']);
  });

  it('shows test accounts when asked', () => {
    expect(filterRows(rows, { query: '', hideTestAccounts: false }).map((r) => r.user_id)).toEqual(['1', '2']);
  });

  it('matches the query against name, username and email, case-insensitively', () => {
    expect(filterRows(rows, { query: 'RACH', hideTestAccounts: true }).map((r) => r.user_id)).toEqual(['1']);
    expect(filterRows(rows, { query: 'dzierson', hideTestAccounts: false }).map((r) => r.user_id)).toEqual(['2']);
    expect(filterRows(rows, { query: 'zzz', hideTestAccounts: false })).toEqual([]);
  });
});

describe('sortRows', () => {
  const rows = [
    row({ user_id: 'a', total_logins: 5, last_active_at: null, display_name: 'Zed' }),
    row({ user_id: 'b', total_logins: 50, last_active_at: '2026-09-01T00:00:00Z', display_name: 'amy' }),
    row({ user_id: 'c', total_logins: 20, last_active_at: '2026-09-07T00:00:00Z', display_name: 'Bob' }),
  ];

  it('sorts numbers by the direction flag', () => {
    expect(sortRows(rows, 'total_logins', 'desc', now).map((r) => r.user_id)).toEqual(['b', 'c', 'a']);
    expect(sortRows(rows, 'total_logins', 'asc', now).map((r) => r.user_id)).toEqual(['a', 'c', 'b']);
  });

  it('puts missing dates last in either direction', () => {
    expect(sortRows(rows, 'last_active_at', 'desc', now).map((r) => r.user_id)).toEqual(['c', 'b', 'a']);
    expect(sortRows(rows, 'last_active_at', 'asc', now).map((r) => r.user_id)).toEqual(['b', 'c', 'a']);
  });

  it('sorts the derived per-day rate', () => {
    const rated = [
      row({ user_id: 'slow', total_logins: 10, created_at: '2026-08-29T12:00:00Z' }), // 1/day
      row({ user_id: 'fast', total_logins: 10, created_at: '2026-09-06T12:00:00Z' }), // 5/day
    ];
    expect(sortRows(rated, 'per_day', 'desc', now).map((r) => r.user_id)).toEqual(['fast', 'slow']);
  });

  it('sorts names case-insensitively', () => {
    expect(sortRows(rows, 'name', 'asc', now).map((r) => r.user_id)).toEqual(['b', 'c', 'a']);
  });

  it('does not mutate the input', () => {
    const copy = [...rows];
    sortRows(rows, 'total_logins', 'desc', now);
    expect(rows).toEqual(copy);
  });
});
