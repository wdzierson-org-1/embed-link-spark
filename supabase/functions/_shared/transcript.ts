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
