import { describe, expect, it } from 'vitest';
import { DUE_WINDOW_MS, parseRemindAt } from './reminders';

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
