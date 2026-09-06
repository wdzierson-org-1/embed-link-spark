import {
  clearReminderPatch,
  orderDueFirst,
  remindAtForPreset,
  reminderLabel,
  reminderState,
  ReminderFields,
  setReminderPatch,
} from './reminders';

const now = new Date('2026-09-06T12:00:00.000Z');
const at = (iso: string) => ({ remind_at: iso, reminder_cleared_at: null });

describe('reminderState', () => {
  it('is none without remind_at', () => {
    expect(reminderState({}, now)).toBe('none');
    expect(reminderState({ remind_at: null }, now)).toBe('none');
  });
  it('is scheduled before remind_at', () => {
    expect(reminderState(at('2026-09-06T12:00:01Z'), now)).toBe('scheduled');
  });
  it('is due from remind_at up to (not including) remind_at + 24h', () => {
    expect(reminderState(at('2026-09-06T12:00:00Z'), now)).toBe('due');
    expect(reminderState(at('2026-09-05T12:00:01Z'), now)).toBe('due');
    expect(reminderState(at('2026-09-05T12:00:00Z'), now)).toBe('cleared');
  });
  it('cleared_at wins over everything', () => {
    expect(reminderState({ remind_at: '2026-09-06T12:00:00Z', reminder_cleared_at: '2026-09-06T12:30:00Z' }, now)).toBe('cleared');
    expect(reminderState({ remind_at: '2026-09-09T12:00:00Z', reminder_cleared_at: '2026-09-06T12:30:00Z' }, now)).toBe('cleared');
  });
});

describe('remindAtForPreset', () => {
  it('adds whole days', () => {
    expect(remindAtForPreset(1, now)).toBe('2026-09-07T12:00:00.000Z');
    expect(remindAtForPreset(3, now)).toBe('2026-09-09T12:00:00.000Z');
    expect(remindAtForPreset(5, now)).toBe('2026-09-11T12:00:00.000Z');
  });
});

describe('orderDueFirst', () => {
  const items: (ReminderFields & { id: string })[] = [
    { id: 'newest', ...at('2026-09-10T00:00:00Z') },           // scheduled
    { id: 'plain' },                                            // none
    { id: 'due-later', ...at('2026-09-06T09:00:00Z') },        // due
    { id: 'expired', ...at('2026-09-01T00:00:00Z') },          // cleared by window
    { id: 'due-earlier', ...at('2026-09-05T20:00:00Z') },      // due, waiting longest
    { id: 'dismissed', remind_at: '2026-09-06T01:00:00Z', reminder_cleared_at: '2026-09-06T02:00:00Z' },
  ];
  it('puts due items first by remind_at asc and keeps the rest in incoming order', () => {
    expect(orderDueFirst(items, now).map((i) => i.id)).toEqual([
      'due-earlier', 'due-later', 'newest', 'plain', 'expired', 'dismissed',
    ]);
  });
  it('does not mutate its input', () => {
    const copy = [...items];
    orderDueFirst(items, now);
    expect(items).toEqual(copy);
  });
});

describe('reminderLabel', () => {
  it('describes each state', () => {
    expect(reminderLabel({}, now)).toBeNull();
    expect(reminderLabel(at('2026-09-06T12:00:00Z'), now)).toBe('Due');
    expect(reminderLabel(at('2026-09-06T17:00:00Z'), now)).toBe('in 5h');
    expect(reminderLabel(at('2026-09-06T12:10:00Z'), now)).toBe('in 1h');
    expect(reminderLabel(at('2026-09-09T12:00:00Z'), now)).toBe('in 3d');
    expect(reminderLabel(at('2026-09-08T18:00:00Z'), now)).toBe('in 2d');
    expect(reminderLabel(at('2026-09-01T00:00:00Z'), now)).toBeNull();
  });
});

describe('patches', () => {
  it('setReminderPatch resets cleared and notified', () => {
    expect(setReminderPatch('2026-09-09T12:00:00.000Z')).toEqual({
      remind_at: '2026-09-09T12:00:00.000Z', reminder_cleared_at: null, reminder_notified_at: null,
    });
  });
  it('clearReminderPatch stamps now', () => {
    expect(clearReminderPatch(now)).toEqual({ reminder_cleared_at: '2026-09-06T12:00:00.000Z' });
  });
});
