// supabase/functions/_shared/reminders.ts
//
// Reminder contract shared by the capture endpoints and the daily job.
// Import-free so it runs under Deno and vitest. Spec:
// docs/superpowers/specs/2026-09-06-reminders-design.md

/** A reminder is "due" for exactly this long after remind_at unless cleared. */
export const DUE_WINDOW_MS = 24 * 60 * 60 * 1000;

/** How far in the past a client-supplied remind_at may sit and still count. */
const PAST_TOLERANCE_MS = 60 * 60 * 1000;

/**
 * Validate a caller-supplied `remind_at`. Returns a canonical ISO-8601 UTC
 * string, or null for anything unusable — capture never fails over metadata,
 * so callers treat null as "no reminder" and log, never 4xx.
 */
export function parseRemindAt(value: unknown, now: Date = new Date()): string | null {
  if (typeof value !== 'string' || value.trim() === '') return null;
  const ms = Date.parse(value);
  if (Number.isNaN(ms)) return null;
  if (ms < now.getTime() - PAST_TOLERANCE_MS) return null;
  return new Date(ms).toISOString();
}
