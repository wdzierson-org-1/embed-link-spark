import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { runEnrichmentMaintenance } from './enrichmentMaintenance';
import { assessEnrichment } from './enrichmentQuality';
import { prepareRepair } from './enrichmentRepair';
import { generateSummary } from './summarize';

vi.mock('./summarize.ts', async importOriginal => {
  const actual = await importOriginal<typeof import('./summarize')>();
  return { ...actual, generateSummary: vi.fn(async () => 'Synthetic recording summary.'),
    deriveTitleFromContent: vi.fn(async () => 'Synthetic title') };
});

const CAPTION = 'A synthetic caption describing this fixture video but containing none of its spoken details.';
const TRANSCRIPT = 'Synthetic transcript: the presenter explains how the experimental component operates and gives three concrete examples.';
const CAPTURE = { success: true, kind: 'transcript', source: 'transcriptfetch-instagram', text: TRANSCRIPT,
  facts: { language: 'en', durationS: 64, author: 'Synthetic creator', description: 'Synthetic original video description.' } };
const TRANSCRIPT_EVIDENCE = { capture_kind: 'transcript', transcript: true, transcript_source: CAPTURE.source,
  language: 'en', duration_s: 64, author: 'Synthetic creator' };
let interceptedFetch: ReturnType<typeof vi.fn>;

beforeEach(() => {
  vi.clearAllMocks();
  interceptedFetch = vi.fn(async () => { throw new Error('Unexpected network request'); });
  vi.stubGlobal('fetch', interceptedFetch);
});
afterEach(() => vi.unstubAllGlobals());

function fixture(overrides: Record<string, unknown> = {}) {
  return { id: 'synthetic-item', user_id: 'synthetic-owner', type: 'link',
    url: 'https://www.instagram.com/reel/synthetic-fixture/', title: 'Synthetic saved video',
    description: 'Synthetic initial video description.', summary: null, page_body: null,
    attributes: { enrichment: { evidence: {} } }, ...overrides };
}

async function review(options: { item?: Record<string, unknown>; state?: Record<string, unknown>; capture?: unknown;
  freshProviderCaption?: boolean; providerPending?: boolean; attempts?: number; indexSuccess?: boolean; captureReject?: boolean } = {}) {
  const item: any = fixture(options.item);
  const before = assessEnrichment(item, false);
  const job = { item_id: item.id, attempts: options.attempts ?? 0, lease_token: 'synthetic-lease', revision: 1,
    provider_state: options.state || {} };
  const patches: any[] = []; const attempts: any[] = []; const qualities: any[] = [];
  if (options.freshProviderCaption || options.providerPending) {
    interceptedFetch.mockImplementation(async (url: string) => {
      if (url.startsWith('https://api.supadata.ai/v1/metadata?')) return new Response(JSON.stringify({ description: CAPTION }), { status: 200 });
      if (url.startsWith('https://api.supadata.ai/v1/transcript?')) return new Response(JSON.stringify(options.providerPending
        ? { jobId: 'queued-transcript', status: 'queued' } : { status: 'failed', content: '' }), { status: options.providerPending ? 202 : 200 });
      throw new Error('Unexpected mocked provider route');
    });
  }
  const rpc = vi.fn(async (name: string, args: any) => {
    if (name === 'apply_enrichment_patch') {
      patches.push(structuredClone(args));
      Object.assign(item, args.patch);
      item.attributes.enrichment.evidence = { ...item.attributes.enrichment.evidence, ...args.evidence_patch };
    }
    return { data: name === 'begin_enrichment_run' ? 'synthetic-run' :
      name === 'claim_enrichment_jobs' ? [job] : name === 'reserve_enrichment_repair' ? true :
      ['enrichment_source_metrics', 'pending_enrichment_evals'].includes(name) ? [] : true };
  });
  const db = { rpc, from: (table: string) => {
    const value = table === 'items' ? item : table === 'enrichment_sources' ? [] : null;
    const query: any = {
      select: () => query, eq: () => query, update: () => query,
      maybeSingle: async () => ({ data: value }), single: async () => ({ data: value }),
      upsert: async (record: any) => { if (table === 'enrichment_quality') qualities.push(structuredClone(record)); return { data: null }; },
      insert: async (record: any) => { if (table === 'enrichment_attempts') attempts.push(structuredClone(record)); return { data: null }; },
      then: (resolve: (value: unknown) => unknown) => Promise.resolve({ data: value }).then(resolve),
    };
    return query;
  } };
  const call = vi.fn(async (name: string) => {
    if (name === 'scrape-page-content') {
      if (options.captureReject) throw new Error('Synthetic caller timeout');
      return structuredClone(options.capture === undefined ? CAPTURE : options.capture);
    }
    if (name === 'generate-embeddings') return { success: options.indexSuccess ?? true };
    throw new Error('Unexpected mocked function route: ' + name);
  });
  const result = await runEnrichmentMaintenance({ db, call, now: () => 0, config: {
    repairsEnabled: true, openAiKey: 'synthetic-key-never-sent',
    socialKey: options.freshProviderCaption || options.providerPending ? 'synthetic-social-key-never-sent' : undefined,
    visualEnabled: false, dailyRepairLimit: 10, repairsPerRun: 1, maxItems: 1,
  } });
  return { item, before, patches, call, result, attempts, qualities, rpc,
    summaryInputs: vi.mocked(generateSummary).mock.calls.map(([, input]) => input),
    finish: rpc.mock.calls.find(([name]) => name === 'finish_enrichment_job')![1] };
}

describe('maintenance transcript capture handoff', () => {
  it('applies the extractOnly body under the existing lease and snapshot contract', async () => {
    const r = await review();
    expect(r.call).toHaveBeenCalledWith('scrape-page-content', { itemId: r.item.id, url: r.item.url, extractOnly: true });
    expect(r.patches[0]).toMatchObject({ patch: { page_body: TRANSCRIPT }, strategy_name: CAPTURE.source });
    expect(r.finish).toMatchObject({ token: 'synthetic-lease', expected_revision: 1, spent_attempt: true, next_provider_state: { page_attempted: true } });
    expect(interceptedFetch).not.toHaveBeenCalled();
    expect(r.result).toMatchObject({ failed: 0 });
  });
  it('preserves transcript kind, provider, and facts', async () => {
    const r = await review();
    expect(r.patches[0].evidence_patch).toMatchObject(TRANSCRIPT_EVIDENCE);
  });
  it('summarizes a recovered link transcript in the video lane', async () => {
    expect((await review()).summaryInputs[0].kind).toBe('video');
  });
  it.each(['https://www.youtube.com/watch?v=synthetic', 'https://www.tiktok.com/@fixture/video/123'])('recovers missing video evidence even with an existing usable caption: %s', async url => {
    const r = await review({ state: { oembed_done: true }, item: { url, page_body: CAPTION, summary: 'Prior caption summary.',
      attributes: { enrichment: { evidence: { caption: true, capture_kind: 'caption' } } } } });
    expect(r.before.reasons).toContain('missing_media_evidence');
    expect(r.call).toHaveBeenCalledWith('scrape-page-content', { itemId: r.item.id, url: r.item.url, extractOnly: true });
    expect(r.item.page_body).toBe(TRANSCRIPT);
  });
  it.each(['https://www.youtube.com/watch?v=synthetic', 'https://www.tiktok.com/@fixture/video/123'])('recovers missing video evidence after a fresh provider caption and failed transcript: %s', async url => {
    const r = await review({ freshProviderCaption: true, item: { url } });
    expect(interceptedFetch).toHaveBeenCalledTimes(2);
    expect(r.call).toHaveBeenCalledWith('scrape-page-content', { itemId: r.item.id, url: r.item.url, extractOnly: true });
    expect(r.item.page_body).toBe(TRANSCRIPT);
  });
  it.each([false, true])('does not newly submit Instagram caption recovery until jobs are durable (fresh caption: %s)', async freshProviderCaption => {
    const r = await review({ freshProviderCaption, item: freshProviderCaption ? {} : { page_body: CAPTION } });
    expect(r.call.mock.calls.some(([name]) => name === 'scrape-page-content')).toBe(false);
    expect(r.item.page_body).toBe(CAPTION);
    expect(r.item.attributes.enrichment.evidence.transcript).not.toBe(true);
    expect(r.finish.next_provider_state).not.toHaveProperty('page_attempted');
  });
  it.todo('recover an existing Instagram caption after TranscriptFetch job IDs and polling are durable');
  it.todo('recover a fresh Instagram provider caption after TranscriptFetch job IDs and polling are durable');
  it('clears superseded provider errors and unavailable retry timing after successful fallback', async () => {
    const r = await review();
    expect(r.qualities[0].reasons).not.toContain('social_provider_unconfigured');
    expect(r.attempts[0].reasons).not.toContain('social_provider_unconfigured');
    expect(r.finish.delay_hours).toBe(1);
  });
  it('keeps a useful fresh caption and the provider failure if capture is rejected', async () => {
    const r = await review({ freshProviderCaption: true, item: { url: 'https://www.youtube.com/watch?v=synthetic' },
      capture: { ...CAPTURE, text: 'No transcript available' } });
    expect(r.item.page_body).toBe(CAPTION);
    expect(r.item.attributes.enrichment.evidence).toEqual({ caption: true });
    expect(r.attempts[0].reasons).toContain('transcript_unavailable');
    expect(r.summaryInputs[0].kind).toBe('link');
  });
  it('persists the one-shot attempt and updated social state when fallback rejects', async () => {
    const r = await review({ freshProviderCaption: true, item: { url: 'https://www.youtube.com/watch?v=synthetic' }, captureReject: true });
    expect(r.finish.next_provider_state).toEqual({ metadata: true, transcript_done: true, page_attempted: true });
    expect(r.item.page_body).toBe(CAPTION);
    expect(r.item.attributes.enrichment.evidence).toEqual({ caption: true });
    expect(r.attempts[0].reasons).toContain('page_capture_failed');
    expect(r.summaryInputs[0].kind).toBe('link');
  });
  it('persists the one-shot attempt when legacy no-content fallback rejects', async () => {
    const error = vi.spyOn(console, 'error').mockImplementation(() => {});
    try {
      const r = await review({ captureReject: true });
      expect(r.finish.next_provider_state).toEqual({ page_attempted: true });
      expect(r.item.page_body).toBeNull();
      expect(r.item.attributes.enrichment.evidence).toEqual({});
      expect(r.attempts[0].reasons).toContain('page_capture_failed');
    } finally { error.mockRestore(); }
  });
  it.each(['transcript', 'visual'])('does not start fallback while a retained %s job exists without a provider key', async key => {
    const state = { [key]: { id: 'pending-job', started: '2026-10-10T12:00:00Z', polls: 2 } };
    const r = await review({ state, attempts: 5 });
    expect(r.call.mock.calls.some(([name]) => name === 'scrape-page-content')).toBe(false);
    expect(r.finish.next_provider_state).toEqual(state);
    expect(r.finish.spent_attempt).toBe(false);
  });
  it('does not start fallback while a newly queued provider job is pending', async () => {
    const r = await review({ providerPending: true });
    expect(r.call.mock.calls.some(([name]) => name === 'scrape-page-content')).toBe(false);
    expect(r.finish.next_provider_state.transcript.id).toBe('queued-transcript');
    expect(r.finish.delay_hours).toBe(1);
  });
  it('respects the persisted one-shot page attempt guard', async () => {
    const r = await review({ state: { page_attempted: true } });
    expect(r.call.mock.calls.some(([name]) => name === 'scrape-page-content')).toBe(false);
    expect(r.finish.next_provider_state).toEqual({ page_attempted: true });
  });
  it('does not infer an Instagram /p/ post is a video from its caption', async () => {
    const r = await review({ item: { url: 'https://www.instagram.com/p/synthetic-fixture/', page_body: CAPTION } });
    expect(r.before.reasons).toContain('missing_visual_evidence');
    expect(r.call.mock.calls.some(([name]) => name === 'scrape-page-content')).toBe(false);
  });
  it('preserves and summarizes an existing richer transcript without another capture', async () => {
    const r = await review({ item: { page_body: TRANSCRIPT, attributes: { enrichment: { evidence: TRANSCRIPT_EVIDENCE } } } });
    expect(r.call.mock.calls.some(([name]) => name === 'scrape-page-content')).toBe(false);
    expect(r.item.page_body).toBe(TRANSCRIPT);
    expect(r.item.attributes.enrichment.evidence).toEqual(TRANSCRIPT_EVIDENCE);
    expect(r.summaryInputs[0].kind).toBe('video');
  });
  it.each(['Instagram', 'Synthetic initial video description.'])('preserves source descriptions when current description is %s', async description => {
    const r = await review({ item: { description } });
    expect(r.item.summary).toBe('Synthetic recording summary.');
    expect(r.item.description).toBe(description === 'Instagram' ? CAPTURE.facts.description : description);
  });
  it('fills an empty description from summary when no source description is available', async () => {
    const r = await review({ item: { description: null }, capture: { ...CAPTURE, facts: {} } });
    expect(r.item.description).toBe('Synthetic recording summary.');
  });
  it('preserves meaningful descriptions that happen to end with on YouTube', async () => {
    const description = 'Detailed interview with Grace Hopper on YouTube';
    const r = await review({ item: { url: 'https://www.youtube.com/watch?v=synthetic', description } });
    expect(r.item.page_body).toBe(TRANSCRIPT);
    expect(r.item.description).toBe(description);
  });
  it('accepts real short speech', async () => {
    const r = await review({ capture: { ...CAPTURE, text: 'Turn left at the red door.' } });
    expect(r.item.page_body).toBe('Turn left at the red door.');
    expect(r.item.attributes.enrichment.evidence.transcript).toBe(true);
  });
  it.each([
    { ...CAPTURE, kind: 'unexpected' }, { ...CAPTURE, text: { text: TRANSCRIPT } },
    { ...CAPTURE, text: '  ' }, { ...CAPTURE, text: 'No transcript available' },
    { ...CAPTURE, success: false },
  ])('rejects invalid captures without adding body facts: %j', async capture => {
    const r = await review({ capture });
    expect(r.result).toMatchObject({ failed: 0 });
    expect(r.item.page_body).toBeNull();
    expect(r.item.attributes.enrichment.evidence).toEqual({});
    expect(r.summaryInputs).toEqual([]);
    expect(r.attempts[0].reasons).toContain('social_provider_unconfigured');
  });
  it.each(['caption', 'page'])('does not turn %s preview facts into transcript evidence', async kind => {
    const r = await review({ capture: { ...CAPTURE, kind, text: CAPTION } });
    expect(r.item.page_body).toBe(CAPTION);
    expect(r.item.attributes.enrichment.evidence).toEqual({ capture_kind: kind, ...(kind === 'caption' ? { caption: true } : {}) });
    expect(r.summaryInputs[0].kind).toBe('link');
  });
  it('preserves a caption accepted at the Instagram chrome boundary', async () => {
    const r = await review({ capture: { ...CAPTURE, kind: 'caption', text: 'More options\nA useful original caption.\nLoad more comments' } });
    expect(r.item.page_body).toBe('A useful original caption.');
    expect(r.item.attributes.enrichment.evidence).toEqual({ capture_kind: 'caption', caption: true });
  });
  it('keeps OCR capture text in the page lane without transcript facts', async () => {
    const r = await review({ capture: { ...CAPTURE, kind: 'ocr', text: 'A readable label.' } });
    expect(r.item.page_body).toBe('A readable label.');
    expect(r.item.attributes.enrichment.evidence).toEqual({ capture_kind: 'ocr' });
    expect(r.summaryInputs[0].kind).toBe('link');
  });
  it('omits invalid optional facts while retaining valid transcript evidence', async () => {
    const r = await review({ capture: { ...CAPTURE, facts: { language: [], durationS: -2, author: {}, description: 12 } } });
    expect(r.item.attributes.enrichment.evidence).toEqual({ capture_kind: 'transcript', transcript: true, transcript_source: CAPTURE.source });
    expect(r.item.description).toBe('Synthetic initial video description.');
  });
  it('maps transcript capture evidence for a generic page adapter too', async () => {
    const r = await review({ item: { url: 'https://example.com/watch/demo' } });
    expect(r.patches[0].evidence_patch).toMatchObject(TRANSCRIPT_EVIDENCE);
    expect(r.summaryInputs[0].kind).toBe('video');
  });
  it('retains a real indexing failure after successful fallback', async () => {
    const error = vi.spyOn(console, 'error').mockImplementation(() => {});
    try {
      const r = await review({ indexSuccess: false });
      expect(r.result).toMatchObject({ failed: 1 });
      expect(r.attempts[0].reasons).toEqual(['index_update_failed']);
    } finally { error.mockRestore(); }
  });
});

describe('repair evidence follows the body that is actually accepted', () => {
  it('does not overwrite existing transcript provenance with a caption capture', () => {
    const item = fixture({ page_body: TRANSCRIPT, attributes: { enrichment: { evidence: TRANSCRIPT_EVIDENCE } } });
    const prepared = prepareRepair(item, { strategy: 'caption-provider', text: CAPTION, evidence: { capture_kind: 'caption', caption: true } });
    expect(prepared.patch).not.toHaveProperty('page_body');
    expect(prepared.evidence).toEqual({});
  });
  it('does not retain transcript metadata when the candidate transcript is unusable', () => {
    const prepared = prepareRepair(fixture(), { strategy: CAPTURE.source, text: 'No transcript available', evidence: TRANSCRIPT_EVIDENCE });
    expect(prepared.evidence).toEqual({});
    expect(prepared.sourceText).toBe('');
  });
});
