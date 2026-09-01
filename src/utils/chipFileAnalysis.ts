// Orchestrates chip-time file understanding, mirroring hydrateLinkMetadata's
// role for links: local extraction and staged upload run in parallel from t0,
// then the per-type edge function turns the uploaded file (plus any locally
// extracted snippet) into a smart title/summary. Every stage is non-fatal.

import { supabase } from '@/integrations/supabase/client';
import { analyzeFileLocally, type LocalFileFacts } from './localFileAnalysis';
import { uploadToStaging } from './stagedUploader';

export type ChipFileKind = 'image' | 'video' | 'audio' | 'document';

export interface FileAnalysis extends LocalFileFacts {
  title?: string;
  description?: string;
  transcription?: string;
  detectedText?: string;
  tags?: string[];
  uploadedFilePath?: string;
}

export interface ChipAnalysisUpdate {
  analysis?: Partial<FileAnalysis>;
  uploadState?: 'uploading' | 'done' | 'failed';
  uploadProgress?: number;
  analysisState?: 'local' | 'analyzing' | 'ready';
}

export interface ChipAnalysisHandle {
  done: Promise<FileAnalysis>;
  abort: () => void;
}

const getPublicUrl = (path: string): string =>
  supabase.storage.from('stash-media').getPublicUrl(path).data.publicUrl;

const analyzeUploadedFile = async (
  file: File,
  kind: ChipFileKind,
  uploadedPath: string,
  snippet: string | undefined
): Promise<Partial<FileAnalysis> | null> => {
  if (kind === 'image') {
    const { data, error } = await supabase.functions.invoke('analyze-image', {
      body: { imageUrl: getPublicUrl(uploadedPath) },
    });
    if (error || !data?.success) return null;
    const detected =
      typeof data.detected_text === 'string' &&
      data.detected_text.trim() &&
      data.detected_text.trim().toLowerCase() !== 'none'
        ? data.detected_text.trim()
        : undefined;
    // Vision titles ("Screenshot of X" / "Image of X") replace filename
    // titles; the filename itself rides in attributes.media.file_name
    const title =
      typeof data.title === 'string' && data.title.trim() ? data.title.trim() : undefined;
    return { title, description: data.description, detectedText: detected, tags: data.tags };
  }

  if (kind === 'audio') {
    const { data, error } = await supabase.functions.invoke('transcribe-audio', {
      body: { audioUrl: getPublicUrl(uploadedPath), fileName: file.name },
    });
    if (error || !data) return null;
    return { description: data.description, transcription: data.transcription };
  }

  // Documents (PDF and everything else): content-based when we have a snippet,
  // filename-based guess otherwise — same graceful ladder as before.
  const { data, error } = await supabase.functions.invoke('quick-pdf-summary', {
    body: { fileName: file.name, snippet },
  });
  if (error || !data) return null;
  return { title: data.title, description: data.description };
};

export const analyzeDroppedFile = (
  file: File,
  kind: ChipFileKind,
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

    let uploadedPath: string | null = null;
    try {
      uploadedPath = await uploadRun;
    } catch (error) {
      if (error instanceof DOMException && error.name === 'AbortError') {
        return accumulated;
      }
      console.error('Staged upload failed (chip will fall back to save-time upload):', error);
      emit({ uploadState: 'failed' });
    }

    if (controller.signal.aborted) return accumulated;

    if (uploadedPath && kind !== 'video') {
      emit({ analysisState: 'analyzing' });
      try {
        const serverAnalysis = await analyzeUploadedFile(file, kind, uploadedPath, accumulated.snippet);
        if (serverAnalysis) emit({ analysis: serverAnalysis });
      } catch (error) {
        console.error('Chip server analysis failed (non-fatal):', error);
      }
    }

    emit({ analysisState: 'ready' });
    return accumulated;
  })();

  return {
    done,
    abort: () => controller.abort(),
  };
};
