// Chip-time file understanding: the local facts (pages, duration, dimensions, the PDF's own
// title, a thumbnail) and the staged upload run in parallel from t0, so the chip can say what
// it holds and the save needs no second upload. Nothing here enriches — titles, descriptions,
// OCR, transcripts and summaries come from the platform's add-file pipeline after the save,
// the same for every client (docs/ETHOS.md). Every stage is non-fatal.

import { analyzeFileLocally, type LocalFileFacts } from './localFileAnalysis';
import { uploadToStaging } from './stagedUploader';

export type ChipFileKind = 'image' | 'video' | 'audio' | 'document';

export interface FileAnalysis extends LocalFileFacts {
  uploadedFilePath?: string;
}

export interface ChipAnalysisUpdate {
  analysis?: Partial<FileAnalysis>;
  uploadState?: 'uploading' | 'done' | 'failed';
  uploadProgress?: number;
  /** `local` while the file is being read; `ready` once the chip knows all it will */
  analysisState?: 'local' | 'ready';
}

export interface ChipAnalysisHandle {
  done: Promise<FileAnalysis>;
  abort: () => void;
}

export const analyzeDroppedFile = (
  file: File,
  _kind: ChipFileKind,
  userId: string,
  onUpdate: (update: ChipAnalysisUpdate) => void
): ChipAnalysisHandle => {
  const controller = new AbortController();
  const accumulated: FileAnalysis = {};

  const emit = (update: ChipAnalysisUpdate) => {
    if (controller.signal.aborted) return;
    if (update.analysis) Object.assign(accumulated, update.analysis);
    onUpdate(update);
  };

  const localRun = analyzeFileLocally(file)
    .then((facts) => emit({ analysis: facts }))
    .catch(() => undefined);

  const uploadRun = (async () => {
    emit({ uploadState: 'uploading', uploadProgress: 0 });
    const path = await uploadToStaging(
      file,
      userId,
      (percent) => emit({ uploadProgress: percent }),
      { signal: controller.signal }
    );
    emit({ analysis: { uploadedFilePath: path }, uploadState: 'done', uploadProgress: 100 });
    return path;
  })();
  // Rejection is observed via the await below; this keeps it from surfacing as
  // an unhandled rejection if the await hasn't been reached yet.
  void uploadRun.catch(() => undefined);

  const done = (async (): Promise<FileAnalysis> => {
    emit({ analysisState: 'local' });
    await localRun;

    try {
      await uploadRun;
    } catch (error) {
      if (error instanceof DOMException && error.name === 'AbortError') {
        return accumulated;
      }
      console.error('Staged upload failed (the save will upload instead):', error);
      emit({ uploadState: 'failed' });
    }

    if (controller.signal.aborted) return accumulated;

    emit({ analysisState: 'ready' });
    return accumulated;
  })();

  return {
    done,
    abort: () => controller.abort(),
  };
};
