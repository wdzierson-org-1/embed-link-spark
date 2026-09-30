import { describe, expect, it } from 'vitest';
import {
  isTranscribing,
  transcribingLabel,
  transcriptFailureCopy,
  transcriptRefreshKey,
} from './transcriptStatus';

describe('transcriptStatus', () => {
  it('treats pending and processing as in flight, done and failed as settled', () => {
    expect(isTranscribing({ status: 'pending' })).toBe(true);
    expect(isTranscribing({ status: 'processing' })).toBe(true);
    expect(isTranscribing({ status: 'done' })).toBe(false);
    expect(isTranscribing({ status: 'failed' })).toBe(false);
    expect(isTranscribing(undefined)).toBe(false);
  });

  it('changes the refresh key as chunks land', () => {
    expect(transcriptRefreshKey(undefined)).toBeUndefined();
    expect(transcriptRefreshKey({ status: 'processing', chunks_done: 1 })).toBe('processing:1');
    expect(transcriptRefreshKey({ status: 'processing', chunks_done: 2 })).toBe('processing:2');
    expect(transcriptRefreshKey({ status: 'done', chunks_done: 3 })).toBe('done:3');
  });

  it('names the part being transcribed for chunked jobs only', () => {
    expect(transcribingLabel({ status: 'processing', chunks_total: 3, chunks_done: 1 })).toBe('Transcribing… part 2 of 3');
    expect(transcribingLabel({ status: 'processing', chunks_total: 1, chunks_done: 0 })).toMatch(/^Transcribing…/);
    expect(transcribingLabel({ status: 'pending' })).toMatch(/few minutes/);
  });

  it('explains failures and whether a retry is coming', () => {
    expect(transcriptFailureCopy({ status: 'failed', error: 'unsupported_container' })).toMatch(/M4A, MP4 and MOV/);
    expect(transcriptFailureCopy({ status: 'failed', error: 'no_speech' })).toMatch(/No speech/);
    expect(transcriptFailureCopy({ status: 'failed', error: 'transcription_failed', attempts: 1 })).toMatch(/retried automatically/);
    expect(transcriptFailureCopy({ status: 'failed', error: 'transcription_failed', attempts: 3 })).toMatch(/several attempts/);
  });
});
