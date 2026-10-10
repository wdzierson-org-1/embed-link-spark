import { useCallback, useEffect, useId, useMemo, useRef, useState } from 'react';
import { Check, Copy } from 'lucide-react';
import type { ItemAttributes } from '@/types/itemAttributes';
import { captureContent, CaptureError } from '@/utils/captureClient';
import { createObjectDraft, inspectObject, ObjectInteractionError } from '@/utils/objectInteractions';
import type { EvidenceValue, ObjectIntelligence } from '../../../supabase/functions/_shared/objectIntelligence';
import type { ObjectDraftAction, ObjectInteractionDraft } from '../../../supabase/functions/_shared/objectInteractionDraft';
import { ENTITLEMENT_DENIED } from '../../../supabase/functions/_shared/entitlement';
import { SectionHead } from './EditPanelSection';

interface Props {
  item: { id: string; type?: string; url?: string | null; content?: string | null; page_body?: string | null; file_path?: string | null; mime_type?: string | null; attributes?: ItemAttributes };
  userId: string;
  onReady?: (intelligence: ObjectIntelligence | null) => void;
  hiddenFactPaths?: string[];
}

const buttonClass = 'inline-flex min-h-11 items-center justify-center gap-2 border border-ink px-3 py-2 text-[13px] font-medium text-ink transition-colors hover:bg-ink hover:text-white disabled:cursor-default disabled:opacity-50 disabled:hover:bg-transparent disabled:hover:text-ink focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink';
const inputClass = 'w-full min-w-0 rounded-none border border-line bg-white px-3 py-2 text-body text-ink focus:border-ink focus:outline-none focus:ring-[3px] focus:ring-spot';
const actions: Record<ObjectDraftAction, string> = { shopping_list: 'Create a shopping list', recipe_card: 'Create a recipe card', itinerary: 'Create an itinerary' };
const kindLabels: Record<string, string> = { recipe: 'Recipe', travel: 'Travel', product: 'Product', place: 'Place', paper: 'Paper', book: 'Book', event: 'Event', general: 'Saved object' };
const factLabels: Record<string, string> = {
  creator: 'Creator', name: 'Name', title: 'Title', ingredients: 'Ingredients', steps: 'Steps', servings: 'Servings', duration: 'Duration', cuisine: 'Cuisine',
  destination: 'Destination', places: 'Places mentioned', accommodation: 'Places to stay', brand: 'Brand', color: 'Color', material: 'Material', category: 'Category', sku: 'Style / SKU', model: 'Model', size: 'Size', price: 'Price at capture', currency: 'Currency',
  address: 'Address', locality: 'City / locality', price_range: 'Price range', authors: 'Authors', doi: 'DOI', findings: 'Findings', isbn: 'ISBN', starts_at: 'Date / time', location: 'Location', organizer: 'Organizer',
};

function FactRow({ label, values, intelligence }: { label: string; values: EvidenceValue[]; intelligence: ObjectIntelligence }) {
  const ids = new Set(values.flatMap(value => value.evidence_ids));
  const evidence = intelligence.evidence.filter(value => ids.has(value.id));
  return <div className="border-b border-line-soft py-3 last:border-0">
    <dt className="font-pixel text-pixel lowercase text-muted-foreground">{label}</dt>
    <dd className="mt-1 text-sm leading-relaxed text-ink [overflow-wrap:anywhere]">
      {values.length > 1 ? label === 'Steps'
        ? <ol className="list-decimal space-y-1 pl-4">{values.map((value, index) => <li key={index}>{value.value}</li>)}</ol>
        : <ul className="list-disc space-y-1 pl-4">{values.map((value, index) => <li key={index}>{value.value}</li>)}</ul>
        : values[0]?.value}
      {evidence.length > 0 && <details className="mt-1">
        <summary className="w-fit min-h-11 cursor-pointer py-3 text-[12px] text-muted-foreground underline underline-offset-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-ink">View source</summary>
        <div className="space-y-2 border-l border-ink pl-3">
          {evidence.map(entry => <blockquote key={entry.id} className="whitespace-pre-wrap text-[13px] leading-relaxed">{entry.quote}</blockquote>)}
        </div>
      </details>}
    </dd>
  </div>;
}

/** Keying by item and owner discards pending responses and edits when a different object opens. */
export default function ObjectIntelligenceSection(props: Props) {
  return <ObjectIntelligenceContent key={`${props.userId}:${props.item.id}`} {...props} />;
}

function ObjectIntelligenceContent({ item, userId, onReady, hiddenFactPaths = [] }: Props) {
  const [intelligence, setIntelligence] = useState<ObjectIntelligence | null>(null);
  const [status, setStatus] = useState<'loading' | 'ready' | 'pending' | 'unavailable' | 'error'>('loading');
  const [refresh, setRefresh] = useState(0);
  const [refreshing, setRefreshing] = useState(false);
  const [draft, setDraft] = useState<ObjectInteractionDraft | null>(null);
  const [title, setTitle] = useState('');
  const [content, setContent] = useState('');
  const [drafting, setDrafting] = useState<ObjectDraftAction | null>(null);
  const [replaceAction, setReplaceAction] = useState<ObjectDraftAction | null>(null);
  const [error, setError] = useState('');
  const [stale, setStale] = useState(false);
  const [blocked, setBlocked] = useState<'subscription_required' | 'session_required' | 'item_unavailable' | 'account_changed' | null>(null);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [copied, setCopied] = useState(false);
  const mounted = useRef(false), busy = useRef(false), saveBusy = useRef(false), readyCallback = useRef(onReady);
  const formId = useId();
  const titleInput = useRef<HTMLInputElement>(null);
  readyCallback.current = onReady;
  const sourceFingerprint = item.attributes?.object_intelligence?.source_fingerprint;
  const processedAt = item.attributes?.object_intelligence?.processed_at;
  const sourceVersion = useMemo(() => JSON.stringify([
    item.type, item.url, item.content, item.page_body, item.file_path, item.mime_type,
    item.attributes?.enrichment?.evidence, item.attributes?.media?.transcript,
    item.attributes?.link, item.attributes?.object_facts,
  ]), [item.type, item.url, item.content, item.page_body, item.file_path, item.mime_type,
    item.attributes?.enrichment?.evidence, item.attributes?.media?.transcript,
    item.attributes?.link, item.attributes?.object_facts]);

  const showBlocked = useCallback((failure: unknown): boolean => {
    if (!(failure instanceof ObjectInteractionError) && !(failure instanceof CaptureError)) return false;
    if (failure.code === 'subscription_required') {
      setBlocked(failure.code); setError(ENTITLEMENT_DENIED.message); return true;
    }
    if (failure.code === 'session_required') {
      setBlocked(failure.code); setError('Sign in again to use this save.'); return true;
    }
    if (failure.code === 'item_unavailable') {
      setBlocked(failure.code); setError('This save is no longer available.'); return true;
    }
    if (failure.code === 'account_changed') {
      setBlocked(failure.code); setError('Your account changed. Reopen the item before saving.'); return true;
    }
    return false;
  }, []);

  useEffect(() => { mounted.current = true; return () => { mounted.current = false; }; }, []);
  useEffect(() => {
    let active = true, checks = 0;
    let timer: ReturnType<typeof setTimeout> | undefined;
    setIntelligence(null); setStatus('loading'); setRefreshing(true); readyCallback.current?.(null);
    const inspect = async () => {
      try {
        const result = await inspectObject(item.id);
        if (!active) return;
        setStatus(result.status); setRefreshing(false);
        if (result.status === 'ready') {
          setIntelligence(result.intelligence); readyCallback.current?.(result.intelligence); setStale(false);
        } else if (result.status === 'pending' && checks++ < 4) {
          // Five checks total, only while visible. Further work follows realtime or explicit refresh.
          timer = setTimeout(() => { if (document.visibilityState === 'visible') void inspect(); }, 15_000);
        }
      } catch (failure) {
        if (active) { setStatus('error'); setRefreshing(false); showBlocked(failure); }
      }
    };
    void inspect();
    return () => { active = false; if (timer !== undefined) clearTimeout(timer); };
  }, [item.id, sourceFingerprint, processedAt, sourceVersion, refresh, showBlocked]);

  const edited = !!draft && (title !== draft.title || content !== draft.content);
  const earlierSource = !!draft && !!intelligence && draft.source_fingerprint !== intelligence.source_fingerprint;
  const blockingMessage = blocked === 'subscription_required' ? ENTITLEMENT_DENIED.message
    : blocked === 'session_required' ? 'Sign in again to use this save.'
      : blocked === 'account_changed' ? 'Your account changed. Reopen the item before saving.'
      : blocked === 'item_unavailable' ? 'This save is no longer available.' : '';
  const availableActions = intelligence?.capabilities.filter(capability => capability.status === 'source_ready' && capability.effect === 'draft' && Object.prototype.hasOwnProperty.call(actions, capability.id)) ?? [];

  const makeDraft = async (action: ObjectDraftAction) => {
    if (!intelligence || busy.current || saveBusy.current || blocked) return;
    busy.current = true; setDrafting(action); setError(''); setReplaceAction(null); setStale(false);
    try {
      const result = await createObjectDraft(item.id, action, intelligence.source_fingerprint);
      if (!mounted.current) return;
      setDraft(result); setTitle(result.title); setContent(result.content); setSaved(false); setCopied(false);
      requestAnimationFrame(() => { if (mounted.current) titleInput.current?.focus(); });
    } catch (failure) {
      if (!mounted.current) return;
      if (showBlocked(failure)) return;
      if (failure instanceof ObjectInteractionError && ['stale', 'intelligence_unavailable', 'action_unavailable'].includes(failure.code)) {
        setStale(true);
        setError(failure.code === 'stale' ? 'The source changed. Refresh details to make a new draft.'
          : failure.code === 'intelligence_unavailable' ? 'These details are not available for a draft yet. Refresh details to check again.'
            : 'This draft is no longer available from the captured details. Refresh details to see what is available.');
        if (failure.code !== 'action_unavailable') {
          setIntelligence(null); setStatus('unavailable'); readyCallback.current?.(null);
        }
      } else setError(draft ? 'Could not create this draft. Your existing draft is still here. Try again.' : 'Could not create this draft. Try again.');
    } finally { busy.current = false; if (mounted.current) setDrafting(null); }
  };
  const selectAction = (action: ObjectDraftAction) => {
    if (edited && !saved) setReplaceAction(action); else void makeDraft(action);
  };
  const save = async () => {
    if (!draft || !title.trim() || !content.trim() || saved || saveBusy.current || busy.current || blocked) return;
    saveBusy.current = true; setSaving(true); setError('');
    try {
      await captureContent('text', {
        title: title.trim(), content: content.trim(), is_public: false,
        attributes: { derived_from: { version: 1, item_id: draft.source_item_id, source_fingerprint: draft.source_fingerprint, action: draft.action, draft_version: draft.version, created_at: draft.created_at, edited } },
      }, userId);
      if (mounted.current) setSaved(true);
    } catch (failure) {
      if (mounted.current && !showBlocked(failure)) setError('Could not save your draft. Your edits are still here. Try again.');
    }
    finally { saveBusy.current = false; if (mounted.current) setSaving(false); }
  };
  const copy = async () => {
    setError('');
    try { await navigator.clipboard.writeText(`${title}\n\n${content}`); if (mounted.current) setCopied(true); }
    catch { if (mounted.current) setError('Could not copy this draft. Select and copy the text below.'); }
  };
  const refreshDetails = () => { setError(''); setRefresh(value => value + 1); };

  if (status === 'unavailable' && !draft && !error) return null;
  const rows: Array<{ path: string; key: string; values: EvidenceValue[] }> = [];
  if (intelligence) {
    if (intelligence.facts.creator) rows.push({ path: 'creator', key: 'creator', values: [intelligence.facts.creator] });
    const group = intelligence.facts[intelligence.interpretation.kind as keyof typeof intelligence.facts];
    if (group && !('value' in group)) {
      for (const [key, value] of Object.entries(group)) {
        if (value) rows.push({ path: `${intelligence.interpretation.kind}.${key}`, key, values: Array.isArray(value) ? value : [value] });
      }
    }
  }

  return <section className="mt-8 min-w-0" aria-label="Explore this save">
    <SectionHead label="Explore this save" aside={<span className="bg-ink px-1.5 py-0.5 font-pixel text-pixel text-white">beta</span>} />
    {status === 'loading' && <p role="status" className="mt-3 text-sm text-muted-foreground">Checking available details…</p>}
    {status === 'pending' && <div className="mt-3">
      <p role="status" className="text-sm text-muted-foreground">More details are being gathered. You can keep using your save.</p>
      <button type="button" className={`${buttonClass} mt-3`} onClick={refreshDetails}>Refresh details</button>
    </div>}
    {status === 'error' && !blocked && <div className="mt-3">
      <p role="status" className="text-sm text-muted-foreground">Could not load these details. Try again.</p>
      <button type="button" className={`${buttonClass} mt-3`} onClick={refreshDetails}>Refresh details</button>
    </div>}
    {intelligence && <>
      <div className="mt-4">
        <p className="font-pixel text-pixel lowercase text-muted-foreground">Stash’s interpretation</p>
        <p className="mt-1 text-sm leading-relaxed text-ink"><span className="font-medium">{kindLabels[intelligence.interpretation.kind]}</span>{intelligence.interpretation.summary && <> · {intelligence.interpretation.summary}</>}</p>
      </div>
      {rows.some(row => !hiddenFactPaths.includes(row.path)) && <dl className="mt-2">
        {rows.filter(row => !hiddenFactPaths.includes(row.path)).map(row => <FactRow key={row.path} label={factLabels[row.key] ?? row.key} values={row.values} intelligence={intelligence} />)}
      </dl>}
      {intelligence.facts.product?.price && <p className="mt-2 text-[12px] text-muted-foreground">Prices are from the captured source and may have changed.</p>}
      {availableActions.length > 0 && <div className="mt-5">
        <p className="font-pixel text-pixel lowercase text-ink">Make into</p>
        <div className="mt-2 flex flex-wrap gap-2">
          {availableActions.map(action => <button key={action.id} type="button" className={buttonClass} disabled={!!drafting || saving || refreshing || stale || !!blocked} onClick={() => selectAction(action.id as ObjectDraftAction)}>
            {drafting === action.id ? 'Preparing draft…' : actions[action.id as ObjectDraftAction]}
          </button>)}
        </div>
        <p className="mt-2 text-[12px] leading-relaxed text-muted-foreground">Uses the captured details. Review and edit before saving.</p>
      </div>}
    </>}
    {replaceAction && <div className="mt-4 border-y border-ink py-3">
      <p className="text-sm text-ink">Replace your edited draft with a new one?</p>
      <div className="mt-2 flex flex-wrap gap-2">
        <button type="button" className={buttonClass} onClick={() => setReplaceAction(null)}>Keep draft</button>
        <button type="button" className={buttonClass} onClick={() => void makeDraft(replaceAction)}>Replace draft</button>
      </div>
    </div>}
    {(error || blockingMessage) && <div className="mt-4">
      <p role="alert" className="text-sm text-destructive">{blockingMessage || error}</p>
      {stale && <button type="button" className={`${buttonClass} mt-2`} disabled={refreshing} onClick={refreshDetails}>Refresh details</button>}
      {blocked === 'subscription_required' && <a className={`${buttonClass} mt-2`} href="/settings">Manage subscription</a>}
      {blocked === 'session_required' && <a className={`${buttonClass} mt-2`} href="/auth">Sign in</a>}
    </div>}
    {draft && <div className="mt-6 border-t border-ink pt-4" aria-label="Draft preview">
      <p className="font-pixel text-pixel lowercase text-ink">{saved ? 'Saved draft' : 'Your draft'}</p>
      {earlierSource && <p className="mt-2 text-[13px] text-muted-foreground">This draft uses an earlier version of the source.</p>}
      {!intelligence && <p className="mt-2 text-[13px] text-muted-foreground">Current source details could not be verified. This draft uses the previously captured version.</p>}
      {draft.notices.length > 0 && <ul className="mt-2 space-y-1 text-[13px] leading-relaxed text-muted-foreground">{draft.notices.map((notice, index) => <li key={index}>{notice}</li>)}</ul>}
      <label htmlFor={`${formId}-title`} className="mb-1 mt-4 block text-label text-ink">Draft title</label>
      <input ref={titleInput} id={`${formId}-title`} value={title} onChange={event => { setTitle(event.target.value); setCopied(false); }} maxLength={160} disabled={saving || saved || !!drafting} className={`${inputClass} min-h-11`} />
      <label htmlFor={`${formId}-content`} className="mb-1 mt-4 block text-label text-ink">Draft content</label>
      <textarea id={`${formId}-content`} value={content} onChange={event => { setContent(event.target.value); setCopied(false); }} maxLength={24_000} disabled={saving || saved || !!drafting} rows={9} className={`${inputClass} resize-y leading-relaxed`} />
      <div className="mt-3 flex flex-wrap gap-2">
        <button type="button" className={buttonClass} onClick={() => void copy()} disabled={!content.trim()}>{copied ? <Check aria-hidden="true" className="h-4 w-4" /> : <Copy aria-hidden="true" className="h-4 w-4" />}{copied ? 'Copied' : 'Copy draft'}</button>
        <button type="button" className={`${buttonClass} ${saved ? '' : 'bg-ink text-white hover:bg-ink-soft'}`} onClick={() => void save()} disabled={saving || saved || !!drafting || !!blocked || !title.trim() || !content.trim()}>{saving ? 'Saving…' : saved ? 'Saved to Stash' : 'Save to Stash'}</button>
      </div>
      <p role="status" className="mt-2 text-[12px] text-muted-foreground">{saved ? 'Saved as a private note in your Stash.' : 'Saves a new private note.'}</p>
    </div>}
  </section>;
}
