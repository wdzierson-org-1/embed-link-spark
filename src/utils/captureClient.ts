// The web composer's one way in: the platform's capture endpoints — add-note, add-url,
// add-file — exactly as the browser extension, the menubar widget and iOS (through `capture`)
// call them. Nothing is inserted from the browser and nothing is enriched here: titles,
// descriptions, previews, scrapes, transcripts, OCR, summaries and embeddings all land behind
// those endpoints, the same for every client (docs/ETHOS.md "Enrichment is the magic",
// docs/PLATFORM_API.md). The only browser-side work is putting a file into the person's own
// storage folder first, which is add-file's contract.
import { supabase } from '@/integrations/supabase/client';
import { uploadFile } from '@/utils/fileUploader';
import type { ItemAttributes } from '@/types/itemAttributes';

export type CaptureKind = 'text' | 'link' | 'image' | 'audio' | 'video' | 'document';

export interface CaptureInput {
  /** The person's own words about the save: plain text or a Novel JSON document */
  content?: string;
  url?: string;
  /**
   * Files: the original file name (metadata the server keeps). Links never send one — the
   * endpoint treats a caller's title as the person's words and keeps it over the page's own.
   */
  title?: string;
  file?: File;
  /** A chip-time staged upload inside `${userId}/`; without it the file is uploaded at save */
  uploadedFilePath?: string;
  is_public?: boolean;
  attributes?: ItemAttributes;
  remind_at?: string;
}

export interface CapturedItem {
  id: string;
  type?: string;
  title?: string | null;
  [key: string]: unknown;
}

/** Stable classifications for callers that can offer a specific recovery path. */
export type CaptureErrorCode = 'subscription_required' | 'session_required' | 'account_changed' | 'request_failed';
export class CaptureError extends Error {
  constructor(public readonly code: CaptureErrorCode, public readonly status: number | null, message: string) { super(message); }
}

const captureFailure = async (error: unknown): Promise<CaptureError> => {
  const context = (error as { context?: Response } | null)?.context;
  const status = typeof context?.status === 'number' ? context.status : null;
  let serverCode: unknown;
  // Clone before the existing message reader consumes the response; arbitrary
  // provider codes never become action/state classifications in the client.
  try { serverCode = (await context?.clone().json())?.error; } catch { /* Use the generic class. */ }
  const code: CaptureErrorCode = status === 401 || (status === 403 && serverCode === 'session_required') ? 'session_required'
    : status === 403 && serverCode === 'subscription_required' ? 'subscription_required' : 'request_failed';
  return new CaptureError(code, status, await describeFunctionError(error));
};

type Endpoint = 'add-note' | 'add-url' | 'add-file';

const ENDPOINTS: Record<CaptureKind, Endpoint> = {
  text: 'add-note',
  link: 'add-url',
  image: 'add-file',
  audio: 'add-file',
  video: 'add-file',
  document: 'add-file',
};

export const endpointFor = (kind: CaptureKind): Endpoint => ENDPOINTS[kind];

const compact = (body: Record<string, unknown>): Record<string, unknown> =>
  Object.fromEntries(Object.entries(body).filter(([, value]) => value !== undefined));

/**
 * What the endpoint said went wrong. supabase-js keeps the function's Response as `context`
 * on a FunctionsHttpError; the platform answers `{ error, message?, details? }`.
 */
export const describeFunctionError = async (error: unknown): Promise<string> => {
  const fallback = error instanceof Error && error.message ? error.message : 'the server could not save this';
  const context = (error as { context?: { json?: () => Promise<unknown> } } | null)?.context;
  if (typeof context?.json !== 'function') return fallback;
  try {
    const body = (await context.json()) as { message?: unknown; details?: unknown; error?: unknown } | null;
    const said = [body?.message, body?.details, body?.error].find(
      (value): value is string => typeof value === 'string' && value.trim().length > 0,
    );
    return said ?? fallback;
  } catch {
    return fallback;
  }
};

const bodyFor = async (kind: CaptureKind, input: CaptureInput, userId: string): Promise<Record<string, unknown>> => {
  const shared = {
    content: input.content,
    is_public: input.is_public ?? false,
    attributes: input.attributes,
    remind_at: input.remind_at,
  };
  if (kind === 'text') {
    if (!input.content?.trim()) throw new Error('A note needs some words');
    return compact({ ...shared, title: input.title });
  }
  if (kind === 'link') {
    if (!input.url) throw new Error('A link needs an address');
    return compact({ ...shared, url: input.url });
  }
  const filePath = input.uploadedFilePath ?? (input.file ? await uploadFile(input.file, userId) : undefined);
  if (!filePath) throw new Error('A file save needs a file');
  return compact({
    ...shared,
    file_path: filePath,
    mime_type: input.file?.type || 'application/octet-stream',
    file_size: input.file?.size,
    title: input.title ?? input.file?.name,
  });
};

/** Save through the platform; resolves to the row the endpoint created (enrichment follows) */
export const captureContent = async (kind: CaptureKind, input: CaptureInput, userId: string): Promise<CapturedItem> => {
  // Bind the request to the owner who began the save. The SDK otherwise resolves
  // its global token later, which can belong to a different account after a switch.
  const { data: { session }, error: sessionError } = await supabase.auth.getSession();
  if (sessionError || !session?.access_token) throw new CaptureError('session_required', 401, 'Sign in again to save this.');
  if (session.user.id !== userId) throw new CaptureError('account_changed', null, 'Your account changed. Reopen the item before saving.');
  const endpoint = endpointFor(kind);
  const body = await bodyFor(kind, input, userId);
  const { data, error } = await supabase.functions.invoke(endpoint, {
    body, headers: { Authorization: `Bearer ${session.access_token}` },
  });
  if (error) throw await captureFailure(error);
  const item = (data?.item ?? data?.note) as CapturedItem | undefined;
  if (!item?.id) throw new Error(`${endpoint} answered without the saved item`);
  return item;
};
