// Chip-time uploads land in `${userId}/staging/` immediately on drop, with real
// XHR progress (supabase-js upload() cannot report progress). Saved items keep
// their staging path; anything unreferenced after 24h is swept on app load.

import { supabase, SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY } from '@/integrations/supabase/client';

const BUCKET = 'stash-media';
const STAGING_MAX_AGE_MS = 24 * 60 * 60 * 1000;
const SWEEP_LIST_LIMIT = 100;

export const buildStagingPath = (userId: string, fileName: string): string => {
  const ext = fileName.includes('.') ? fileName.split('.').pop() : 'bin';
  const random = Math.random().toString(36).slice(2, 8);
  return `${userId}/staging/${Date.now()}-${random}.${ext}`;
};

const uploadOnce = (
  file: File,
  path: string,
  accessToken: string,
  onProgress: (percent: number) => void,
  signal?: AbortSignal
): Promise<void> =>
  new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open('POST', `${SUPABASE_URL}/storage/v1/object/${BUCKET}/${path}`);
    xhr.setRequestHeader('Authorization', `Bearer ${accessToken}`);
    xhr.setRequestHeader('apikey', SUPABASE_PUBLISHABLE_KEY);
    xhr.setRequestHeader('x-upsert', 'false');
    if (file.type) xhr.setRequestHeader('Content-Type', file.type);
    xhr.upload.onprogress = (event) => {
      if (event.lengthComputable && event.total > 0) {
        onProgress(Math.round((event.loaded / event.total) * 100));
      }
    };
    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) {
        resolve();
      } else {
        reject(new Error(`Staged upload failed with status ${xhr.status}`));
      }
    };
    xhr.onerror = () => reject(new Error('Staged upload failed (network error)'));
    xhr.onabort = () => reject(new DOMException('Staged upload aborted', 'AbortError'));
    signal?.addEventListener('abort', () => xhr.abort(), { once: true });
    xhr.send(file);
  });

export const uploadToStaging = async (
  file: File,
  userId: string,
  onProgress: (percent: number) => void,
  opts: { signal?: AbortSignal } = {}
): Promise<string> => {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session?.access_token) {
    throw new Error('Authentication required for staged upload');
  }

  const path = buildStagingPath(userId, file.name);
  try {
    await uploadOnce(file, path, session.access_token, onProgress, opts.signal);
    return path;
  } catch (error) {
    if (error instanceof DOMException && error.name === 'AbortError') throw error;
    // One automatic retry on a fresh path (a same-ms name collision would 409)
    const retryPath = buildStagingPath(userId, file.name);
    await uploadOnce(file, retryPath, session.access_token, onProgress, opts.signal);
    return retryPath;
  }
};

export const removeStagedFile = async (path: string): Promise<void> => {
  try {
    await supabase.storage.from(BUCKET).remove([path]);
  } catch (error) {
    console.error('Failed to remove staged file (non-fatal):', error);
  }
};

export const sweepStagingOrphans = async (userId: string): Promise<void> => {
  try {
    const prefix = `${userId}/staging`;
    const { data: files, error } = await supabase.storage
      .from(BUCKET)
      .list(prefix, { limit: SWEEP_LIST_LIMIT });
    if (error || !files?.length) return;

    const cutoff = Date.now() - STAGING_MAX_AGE_MS;
    const stalePaths = files
      .filter((file) => file.created_at && new Date(file.created_at).getTime() < cutoff)
      .map((file) => `${prefix}/${file.name}`);
    if (!stalePaths.length) return;

    const [itemRefs, attachmentRefs] = await Promise.all([
      supabase.from('items').select('file_path').in('file_path', stalePaths),
      supabase.from('item_attachments').select('file_path').in('file_path', stalePaths),
    ]);
    const referenced = new Set(
      [...(itemRefs.data ?? []), ...(attachmentRefs.data ?? [])]
        .map((row) => row.file_path)
        .filter(Boolean)
    );

    const orphans = stalePaths.filter((path) => !referenced.has(path));
    if (orphans.length) {
      await supabase.storage.from(BUCKET).remove(orphans);
    }
  } catch (error) {
    console.error('Staging sweep failed (non-fatal):', error);
  }
};
