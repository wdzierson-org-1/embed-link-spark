import { describe, expect, it } from 'vitest';
import { DUE_WINDOW_MS, parseRemindAt, stripReminderColumns } from './reminders';

const now = new Date('2026-09-06T12:00:00.000Z');

describe('parseRemindAt', () => {
  it('returns a canonical ISO string for a valid future timestamp', () => {
    expect(parseRemindAt('2026-09-09T12:00:00Z', now)).toBe('2026-09-09T12:00:00.000Z');
  });
  it('accepts offsets and normalises to UTC', () => {
    expect(parseRemindAt('2026-09-09T08:00:00-04:00', now)).toBe('2026-09-09T12:00:00.000Z');
  });
  it('tolerates up to one hour in the past (clock skew, outbox drains)', () => {
    expect(parseRemindAt('2026-09-06T11:30:00Z', now)).toBe('2026-09-06T11:30:00.000Z');
    expect(parseRemindAt('2026-09-06T10:59:00Z', now)).toBeNull();
  });
  it('accepts the exact boundary of the past tolerance (now - 1h)', () => {
    expect(parseRemindAt('2026-09-06T11:00:00Z', now)).toBe('2026-09-06T11:00:00.000Z');
  });
  it('ignores garbage without throwing', () => {
    expect(parseRemindAt(undefined, now)).toBeNull();
    expect(parseRemindAt(null, now)).toBeNull();
    expect(parseRemindAt('', now)).toBeNull();
    expect(parseRemindAt('soon', now)).toBeNull();
    expect(parseRemindAt(1757160000000, now)).toBeNull();
    expect(parseRemindAt({ at: '2026-09-09' }, now)).toBeNull();
  });
  it('exports the shared 24h window', () => {
    expect(DUE_WINDOW_MS).toBe(24 * 60 * 60 * 1000);
  });
});

describe('stripReminderColumns', () => {
  it('removes all three reminder columns and leaves everything else intact', () => {
    const row = {
      id: 'abc',
      title: 'Hello',
      remind_at: '2026-09-09T12:00:00.000Z',
      reminder_cleared_at: null,
      reminder_notified_at: null,
    };
    expect(stripReminderColumns(row)).toEqual({ id: 'abc', title: 'Hello' });
  });
  it('does not mutate its input', () => {
    const row = { id: 'abc', remind_at: '2026-09-09T12:00:00.000Z' };
    const copy = { ...row };
    stripReminderColumns(row);
    expect(row).toEqual(copy);
  });
  it('is a no-op when the columns are already absent', () => {
    const row = { id: 'abc', title: 'Hello' };
    expect(stripReminderColumns(row)).toEqual({ id: 'abc', title: 'Hello' });
  });
});
