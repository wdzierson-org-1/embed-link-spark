export interface DiarizedTranscript {
  text?: string;
  segments?: { speaker?: string; start?: number; text?: string }[];
}

/** Preserve the recognizer's words; labels identify voices, not inferred people. */
export function formatDiarizedTranscript(result: DiarizedTranscript): string {
  const turns: { speaker: string; start: number; text: string }[] = [];
  for (const segment of result.segments ?? []) {
    const text = segment.text?.trim();
    if (!text) continue;
    const speaker = segment.speaker || 'Unknown';
    const previous = turns[turns.length - 1];
    if (previous?.speaker === speaker) previous.text += ` ${text}`;
    else turns.push({ speaker, start: Math.max(0, segment.start ?? 0), text });
  }
  if (!turns.length) return result.text?.trim() ?? '';
  return turns.map(({ speaker, start, text }) => {
    const seconds = Math.floor(start);
    const stamp = `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
    return `**Speaker ${speaker} · ${stamp}**\n\n${text}`;
  }).join('\n\n');
}

/**
 * Columns to write alongside a chunk's transcript progress.
 *
 * A retry starts with an EMPTY accumulator while the row still holds the
 * PREVIOUS transcript. Writing `page_body: null` at that moment destroys a good
 * transcript before the run has found any speech — and a no-speech run then
 * fails with nothing left to fall back to. So: no new text, no write. The old
 * transcript survives until there is something better to replace it with.
 */
export function transcriptProgressColumns(text: string, cap: number): Record<string, unknown> {
  return text.trim() ? { page_body: text.slice(0, cap) } : {};
}
