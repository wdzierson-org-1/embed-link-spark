import { supabase } from '@/integrations/supabase/client';
import type { ObjectIntelligence } from '../../supabase/functions/_shared/objectIntelligence';
import type { ObjectDraftAction, ObjectInteractionDraft } from '../../supabase/functions/_shared/objectInteractionDraft';

export type ObjectInspection = { status: 'ready'; intelligence: ObjectIntelligence } | { status: 'pending' | 'unavailable' };
export type ObjectInteractionErrorCode = 'stale' | 'subscription_required' | 'session_required' | 'item_unavailable' | 'intelligence_unavailable' | 'action_unavailable' | 'request_failed';
export class ObjectInteractionError extends Error {
  constructor(public readonly code: ObjectInteractionErrorCode) { super(code); }
}

async function responseError(error: unknown): Promise<ObjectInteractionError> {
  const context = (error as { context?: Response } | null)?.context;
  let code: unknown;
  try { code = (await context?.clone().json())?.error; } catch { /* No provider messages enter the UI. */ }
  if (context?.status === 401 || (context?.status === 403 && code === 'session_required')) return new ObjectInteractionError('session_required');
  if (context?.status === 403 && code === 'subscription_required') return new ObjectInteractionError('subscription_required');
  if (context?.status === 404) return new ObjectInteractionError('item_unavailable');
  if (context?.status === 409) {
    if (code === 'source_changed') return new ObjectInteractionError('stale');
    if (code === 'intelligence_unavailable' || code === 'action_unavailable') return new ObjectInteractionError(code);
  }
  return new ObjectInteractionError('request_failed');
}

async function request(body: Record<string, unknown>): Promise<Record<string, unknown>> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    const result = await Promise.race([
      supabase.functions.invoke('object-interactions', { body }),
      new Promise<never>((_, reject) => { timer = setTimeout(() => reject(new ObjectInteractionError('request_failed')), 30_000); }),
    ]);
    if (result.error) {
      throw await responseError(result.error);
    }
    if (!result.data || typeof result.data !== 'object' || Array.isArray(result.data)) throw new ObjectInteractionError('request_failed');
    return result.data;
  } catch (error) {
    throw error instanceof ObjectInteractionError ? error : new ObjectInteractionError('request_failed');
  } finally { if (timer !== undefined) clearTimeout(timer); }
}

/** The endpoint revalidates ownership, current source and evidence. Raw item attributes are not display authority. */
export async function inspectObject(itemId: string): Promise<ObjectInspection> {
  const data = await request({ operation: 'inspect', item_id: itemId });
  if (data.status === 'pending' || data.status === 'unavailable') return { status: data.status };
  const value = data.intelligence as ObjectIntelligence | undefined;
  if (data.status !== 'ready' || !value || value.version !== 1 || !value.facts || !value.interpretation || !Array.isArray(value.evidence) || !Array.isArray(value.capabilities) || !/^[a-f0-9]{64}$/.test(value.source_fingerprint)) throw new ObjectInteractionError('request_failed');
  return { status: 'ready', intelligence: value };
}

export async function createObjectDraft(itemId: string, action: ObjectDraftAction, sourceFingerprint: string): Promise<ObjectInteractionDraft> {
  const data = await request({ operation: 'draft', item_id: itemId, action, source_fingerprint: sourceFingerprint });
  const draft = data.draft as ObjectInteractionDraft | undefined;
  if (!draft || draft.version !== 1 || draft.action !== action || draft.source_item_id !== itemId || draft.source_fingerprint !== sourceFingerprint ||
    typeof draft.title !== 'string' || !draft.title.trim() || draft.title.length > 160 ||
    typeof draft.content !== 'string' || !draft.content.trim() || new TextEncoder().encode(draft.content).byteLength > 24_000 ||
    typeof draft.created_at !== 'string' || !Number.isFinite(Date.parse(draft.created_at)) ||
    !Array.isArray(draft.evidence_ids) || draft.evidence_ids.length > 48 || draft.evidence_ids.some(id => typeof id !== 'string' || !/^e[1-9][0-9]{0,2}$/.test(id)) ||
    !Array.isArray(draft.notices) || draft.notices.length > 4 || draft.notices.some(notice => typeof notice !== 'string' || notice.length > 1000)) throw new ObjectInteractionError('request_failed');
  return draft;
}
