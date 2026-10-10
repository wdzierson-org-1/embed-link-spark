/**
 * Timestamped notes (docs/ui-changes.md 2026-10-10): a note may carry `[m:ss]` or `[h:mm:ss]`
 * markers; the panel renders them as seek points for the save's player. The marker is plain
 * text, so every client (and the shared page) can read it, and only players make it live.
 */
export const TIMESTAMP_PATTERN = /\[(\d{1,2}:)?(\d{1,2}):(\d{2})\]/g;

export const formatTimestamp = (seconds: number): string => {
  const whole = Math.max(0, Math.floor(seconds));
  const h = Math.floor(whole / 3600);
  const m = Math.floor((whole % 3600) / 60);
  const s = whole % 60;
  const ss = String(s).padStart(2, '0');
  return h > 0 ? `${h}:${String(m).padStart(2, '0')}:${ss}` : `${m}:${ss}`;
};

/** `1:42` → 102, `1:02:03` → 3723; null for anything else */
export const parseTimestamp = (text: string): number | null => {
  const match = text.trim().match(/^(?:(\d{1,2}):)?(\d{1,2}):(\d{2})$/);
  if (!match) return null;
  const h = match[1] ? Number(match[1]) : 0;
  const m = Number(match[2]);
  const s = Number(match[3]);
  if (s >= 60 || (match[1] && m >= 60)) return null;
  return h * 3600 + m * 60 + s;
};

/** The marker written into a note for a moment in the media */
export const timestampMarker = (seconds: number): string => `[${formatTimestamp(seconds)}]`;

/** Every marker in a text, with its position and the seconds it names */
export const findTimestamps = (text: string): Array<{ index: number; length: number; seconds: number }> => {
  const found: Array<{ index: number; length: number; seconds: number }> = [];
  for (const match of text.matchAll(TIMESTAMP_PATTERN)) {
    const seconds = parseTimestamp(match[0].slice(1, -1));
    if (seconds !== null && match.index !== undefined) found.push({ index: match.index, length: match[0].length, seconds });
  }
  return found;
};
