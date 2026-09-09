// Copy for the transcript job's status (attributes.media.transcript), shared
// by the detail sheet so iOS/mac can mirror the same words. Pure.

import type { TranscriptState } from '@/types/itemAttributes';

export const isTranscribing = (t?: TranscriptState | null): boolean =>
  t?.status === 'pending' || t?.status === 'processing';

/** A refresh key that changes whenever more transcript may have landed. */
export const transcriptRefreshKey = (t?: TranscriptState | null): string | undefined =>
  t ? `${t.status}:${t.chunks_done ?? 0}` : undefined;

export const transcribingLabel = (t: TranscriptState): string => {
  const total = t.chunks_total ?? 0;
  const done = t.chunks_done ?? 0;
  if (t.status === 'processing' && total > 1 && done < total) {
    return `Transcribing… part ${done + 1} of ${total}`;
  }
  return 'Transcribing… long recordings can take a few minutes.';
};

export const transcriptFailureCopy = (t: TranscriptState): string => {
  const willRetry = (t.attempts ?? 0) < 3;
  switch (t.error) {
    case 'unsupported_container':
      return 'This file is too large to transcribe in its current format. M4A, MP4 and MOV recordings of any length work — try re-exporting it as one of those.';
    case 'no_audio_track':
      return 'No audio track was found in this file.';
    case 'no_speech':
      return 'No speech was detected in this recording.';
    case 'download_failed':
      return willRetry
        ? "The file couldn't be read from storage. It will be retried automatically."
        : "The file couldn't be read from storage.";
    default:
      return willRetry
        ? 'Transcription failed. It will be retried automatically.'
        : 'Transcription failed after several attempts.';
  }
};
