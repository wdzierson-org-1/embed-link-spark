// Explicit reminders — pure logic shared by the grid, the card and the menu.
// Contract: docs/superpowers/specs/2026-09-06-reminders-design.md. iOS mirrors
// this in StashKit's ReminderRules; keep the two in step.

export const DUE_WINDOW_MS = 24 * 60 * 60 * 1000;
const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

export const REMINDER_PRESETS = [1, 3, 5] as const;
export type ReminderPreset = (typeof REMINDER_PRESETS)[number];

export type ReminderState = 'none' | 'scheduled' | 'due' | 'cleared';

export interface ReminderFields {
  remind_at?: string | null;
  reminder_cleared_at?: string | null;
}

export function reminderState(item: ReminderFields, now: Date): ReminderState {
  if (!item.remind_at) return 'none';
  if (item.reminder_cleared_at) return 'cleared';
  const remindAt = Date.parse(item.remind_at);
  if (Number.isNaN(remindAt)) return 'none';
  const t = now.getTime();
  if (t < remindAt) return 'scheduled';
  if (t < remindAt + DUE_WINDOW_MS) return 'due';
  return 'cleared';
}

export function remindAtForPreset(days: ReminderPreset, now: Date): string {
  return new Date(now.getTime() + days * DAY_MS).toISOString();
}

/** Due items first (longest-waiting first), everything else in incoming order. */
export function orderDueFirst<T extends ReminderFields>(items: T[], now: Date): T[] {
  const due: T[] = [];
  const rest: T[] = [];
  for (const item of items) (reminderState(item, now) === 'due' ? due : rest).push(item);
  due.sort((a, b) => Date.parse(a.remind_at!) - Date.parse(b.remind_at!));
  return [...due, ...rest];
}

export function reminderLabel(item: ReminderFields, now: Date): string | null {
  const state = reminderState(item, now);
  if (state === 'due') return 'Due';
  if (state !== 'scheduled') return null;
  const ms = Date.parse(item.remind_at!) - now.getTime();
  if (ms < DAY_MS) return `in ${Math.max(1, Math.ceil(ms / HOUR_MS))}h`;
  return `in ${Math.round(ms / DAY_MS)}d`;
}

export const setReminderPatch = (remindAt: string) => ({
  remind_at: remindAt,
  reminder_cleared_at: null,
  reminder_notified_at: null,
});

export const clearReminderPatch = (now: Date) => ({
  reminder_cleared_at: now.toISOString(),
});
