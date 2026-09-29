import { assessEnrichment, reviewCadence, nextReviewHours, QUALITY_VERSION, type EnrichmentItem } from './enrichmentQuality.ts';
import { prepareRepair, selectRepairAdapter, type RepairCandidate } from './enrichmentRepair.ts';
import { recoverSocial } from './socialEnrichment.ts';
import { applyCandidate, ENRICHMENT_COLUMNS, searchFingerprint } from './enrichmentStore.ts';
import { deriveTitleFromContent, generateSummary, summaryKindFor } from './summarize.ts';
import { searchItems, normalizeSearchRequest, openAiEmbedder } from './search.ts';

interface Config {
  repairsEnabled: boolean; openAiKey?: string; socialKey?: string; visualEnabled: boolean;
  dailyRepairLimit: number; repairsPerRun: number; maxItems: number;
}
interface Deps { db: any; config: Config; call: (name: string, body: unknown) => Promise<any>; now?: () => number; }
const checked = <T>(result: { data: T; error?: unknown }): T => { if (result.error) throw result.error; return result.data; };
const iso = () => new Date().toISOString();

async function indexed(db: any, item: EnrichmentItem) {
  const state = checked<any>(await db.from('enrichment_index_state').select('fingerprint,chunks').eq('item_id', item.id).maybeSingle());
  if (!state || state.chunks < 1 || state.fingerprint !== await searchFingerprint(item)) return false;
  const { count, error } = await db.from('embeddings').select('id', { count: 'exact', head: true }).eq('item_id', item.id);
  if (error) throw error;
  return count === state.chunks;
}
async function signedFile(db: any, item: EnrichmentItem) {
  const path = item.file_path;
  if (!path || !path.startsWith(`${item.user_id}/`) || path.split('/').some(p => p === '.' || p === '..')) throw new Error('missing_owned_file');
  const data = checked<any>(await db.storage.from('stash-media').createSignedUrl(path, 300));
  return data.signedUrl;
}
async function getCandidate(item: EnrichmentItem, job: any, deps: Deps) {
  const { db, config, call } = deps; const adapter = selectRepairAdapter(item);
  let state = job.provider_state || {}; let spent = false;
  let candidate: RepairCandidate = { strategy: adapter };
  if (adapter === 'social') {
    // A rejected page must not suppress the provider's metadata fallback.
    const sourceItem = assessEnrichment(item).status === 'blocked' ? { ...item, page_body: null } : item;
    const social = await recoverSocial(sourceItem, state, { apiKey: config.socialKey, visualEnabled: config.visualEnabled });
    state = social.state; spent = social.spent; candidate = social;
    if (!social.text && !assessEnrichment(item).content_usable && !state.page_attempted && !social.pending) {
      state = { ...state, page_attempted: true }; spent = true;
      const page = await call('scrape-page-content', { itemId: item.id, url: item.url, extractOnly: true });
      if (page.success && page.text) candidate = { ...social, text: page.text, strategy: page.source };
    }
  } else if (adapter === 'page') {
    spent = true;
    const page = await call('scrape-page-content', { itemId: item.id, url: item.url, extractOnly: true });
    candidate = { strategy: page.source || 'page', text: page.success ? page.text : undefined, reason: page.success ? undefined : 'page_unavailable' };
  } else if (['image','transcribe','document'].includes(adapter)) {
    if (!config.openAiKey) return { candidate: { strategy: adapter, unavailable: true, reason: 'model_unconfigured' }, state, spent };
    const fileUrl = await signedFile(db, item); spent = true;
    if (adapter === 'image') {
      const result = await call('analyze-image', { imageUrl: fileUrl });
      candidate = { strategy: 'image-analysis', title: result.title, description: result.description, text: result.detected_text,
        evidence: result.description ? { visual: true, visual_text: result.description, visual_provider: 'analyze-image' } : {} };
    } else if (adapter === 'transcribe') {
      const result = await call('transcribe-audio', { audioUrl: fileUrl, fileName: item.attributes?.media?.file_name || item.title });
      candidate = { strategy: 'transcribe', text: result.transcription, description: result.transcription ? result.description : undefined, evidence: { transcript: !!result.transcription } };
    } else {
      const result = await call(item.mime_type === 'application/pdf' ? 'extract-pdf-text' : 'extract-office-text', {
        itemId: item.id, fileUrl, fileName: item.attributes?.media?.file_name || item.title, mimeType: item.mime_type, extractOnly: true,
      });
      candidate = { strategy: 'document-text', text: result.text, description: result.description, summary: result.summary };
    }
  } else if (adapter === 'unsupported') candidate = { strategy: adapter, unavailable: true, reason: 'unsupported_format' };
  return { candidate, state, spent };
}

/** Quality-driven scheduling and bounded repair, independent of a particular platform or extractor. */
export async function runEnrichmentMaintenance(deps: Deps) {
  const { db, config, call } = deps; const now = deps.now || Date.now; const start = now();
  const token = checked<string | null>(await db.rpc('begin_enrichment_run'));
  if (!token) return { skipped: 'already_running' };
  const counts = { assessed: 0, repaired: 0, deferred: 0, failed: 0, evaluations: 0 };
  let repairSlots = config.repairsPerRun;
  try {
    const sources = checked<any[]>(await db.from('enrichment_sources').select('*')) || [];
    const sourceMap = new Map(sources.map(s => [s.source_key, s]));
    let remaining = config.maxItems;
    while (remaining > 0 && now() - start < 45_000) {
      const jobs = checked<any[]>(await db.rpc('claim_enrichment_jobs', { batch_size: Math.min(remaining, 25), worker_version: QUALITY_VERSION })) || [];
      if (!jobs.length) break;
      for (const job of jobs) {
        remaining--;
        if (now() - start > 70_000) {
          checked(await db.rpc('finish_enrichment_job', { target_id: job.item_id, token: job.lease_token, expected_revision: job.revision, delay_hours: 1, spent_attempt: false, next_provider_state: job.provider_state }));
          counts.deferred++; continue;
        }
        const itemStart = now(); let spent = false; let state = job.provider_state || {}; let delay = 24;
        let failure: string | null = null; let item: EnrichmentItem | null = null; let unmappedType: string | null = null;
        let strategy = 'assessment'; let beforeScore = 0;
        try {
          item = checked<EnrichmentItem | null>(await db.from('items').select(ENRICHMENT_COLUMNS).eq('id', job.item_id).maybeSingle());
          if (!item) continue;
          let quality = assessEnrichment(item, await indexed(db, item)); const before = quality; beforeScore = before.score;
          const source = sourceMap.get(quality.source_key);
          const cadence = source?.cadence || 'hourly';
          let outcome = 'assessed'; let unavailable = false;
          const pending = !!state.transcript || !!state.visual;
          const wantsRepair = quality.status !== 'ready' && quality.status !== 'unsupported' && (job.attempts < 5 || pending);
          if (config.repairsEnabled && wantsRepair && repairSlots > 0 && now() - start < 35_000) {
            const reserved = checked<boolean>(await db.rpc('reserve_enrichment_repair', { token, daily_limit: config.dailyRepairLimit }));
            if (reserved) {
              repairSlots--; spent = true; outcome = 'unchanged';
              const result = await getCandidate(item, job, deps);
              state = result.state; strategy = result.candidate.strategy; unavailable = !!result.candidate.unavailable;
              // Polling an existing job does not spend another retry, but still uses the daily work allowance.
              spent = !pending || result.spent;
              const prepared = prepareRepair(item, result.candidate);
              if (config.openAiKey && prepared.needsTitle) {
                const title = await deriveTitleFromContent(config.openAiKey, prepared.sourceText, item.url);
                if (title) prepared.patch.title = title;
              }
              if (config.openAiKey && prepared.needsSummary && !result.candidate.summary) {
                // Narrow the storage type explicitly; never hand a raw DB type to
                // the prompt selector. null is a known type we must NOT summarize
                // (legacy read-only collections); undefined is an unknown type,
                // which is recorded as a failed attempt below rather than guessing
                // a prompt — a wrong guess writes a bad summary into someone's
                // library, and skipping is always recoverable.
                const summaryKind = summaryKindFor(item.type);
                if (summaryKind === undefined) unmappedType = item.type;
                if (summaryKind) {
                  const summary = await generateSummary(config.openAiKey, { sourceText: prepared.sourceText, kind: summaryKind, title: prepared.patch.title || item.title, url: item.url });
                  if (summary) { prepared.patch.summary = summary; prepared.patch.description = summary.slice(0, 350); }
                }
              }
              if (Object.keys(prepared.patch).length || Object.keys(prepared.evidence).length) {
                const applied = await applyCandidate(db, item, prepared.patch, strategy, prepared.evidence, job.lease_token);
                if (!applied) throw new Error('item_changed');
                item = checked<EnrichmentItem>(await db.from('items').select(ENRICHMENT_COLUMNS).eq('id', job.item_id).single());
              }
              if (config.openAiKey && !await indexed(db, item)) {
                const indexResult = await call('generate-embeddings', { itemId: item.id });
                if (!indexResult.success) throw new Error('index_update_failed');
              }
              quality = assessEnrichment(item, await indexed(db, item));
              outcome = quality.score > before.score || (quality.status === 'ready' && before.status !== 'ready') ? 'improved' : result.candidate.pending ? 'deferred' : result.candidate.reason && !unavailable ? 'failed' : 'unchanged';
              if (result.candidate.pending) delay = 1;
              if (result.candidate.reason) quality.reasons = [...new Set([...quality.reasons, result.candidate.reason])];
              // Surfaces in enrichment_attempts (outcome 'failed') and in
              // enrichment_review_candidates, same as every other enrichment
              // failure, with the offending type named.
              if (unmappedType) { outcome = 'failed'; quality.reasons = [...new Set([...quality.reasons, `unmapped_item_type:${unmappedType}`])]; }
              if (outcome === 'improved') counts.repaired++;
            } else { outcome = 'deferred'; counts.deferred++; }
          } else if (wantsRepair) { outcome = 'deferred'; counts.deferred++; }
          const existing = checked<any>(await db.from('enrichment_quality').select('first_ready_at').eq('item_id', item.id).maybeSingle());
          const { version, ...stored } = quality;
          checked(await db.from('enrichment_quality').upsert({ ...stored, item_id: item.id, user_id: item.user_id, quality_version: version,
            evaluated_at: iso(), first_ready_at: existing?.first_ready_at || (quality.status === 'ready' ? iso() : null) }));
          counts.assessed++;
          if (quality.status !== 'ready') {
            const review = checked<any>(await db.from('enrichment_review_candidates').select('occurrences').eq('item_id', item.id).maybeSingle());
            checked(await db.from('enrichment_review_candidates').upsert({ item_id: item.id, source_key: quality.source_key, reasons: quality.reasons,
              occurrences: (review?.occurrences || 0) + 1, last_seen_at: iso(), resolved_at: null }));
          } else checked(await db.from('enrichment_review_candidates').update({ resolved_at: iso() }).eq('item_id', item.id));
          checked(await db.from('enrichment_attempts').insert({ item_id: item.id, user_id: item.user_id, source_key: quality.source_key, quality_version: QUALITY_VERSION,
            strategy, outcome, before_score: before.score, after_score: quality.score, reasons: quality.reasons, elapsed_ms: now() - itemStart }));
          if (!state.transcript && !state.visual) delay = nextReviewHours(quality.status, cadence, job.attempts + (spent ? 1 : 0), unavailable);
        } catch (error) {
          counts.failed++; failure = error instanceof Error ? error.message : 'maintenance_failed'; delay = nextReviewHours('partial','hourly',job.attempts + (spent ? 1 : 0));
          console.error('enrichment-maintenance item failed', { itemId: job.item_id, reason: failure });
          if (item) checked(await db.from('enrichment_attempts').insert({ item_id: item.id, user_id: item.user_id, source_key: assessEnrichment(item).source_key,
            quality_version: QUALITY_VERSION, strategy, outcome: 'failed', before_score: beforeScore, reasons: [failure], elapsed_ms: now() - itemStart }));
        } finally {
          checked(await db.rpc('finish_enrichment_job', { target_id: job.item_id, token: job.lease_token, expected_revision: job.revision,
            delay_hours: delay, spent_attempt: spent, next_provider_state: state, failure }));
        }
      }
    }
    // Change cadence only at a source's review boundary, so repeated manual runs cannot manufacture a healthy streak.
    const metrics = checked<any[]>(await db.rpc('enrichment_source_metrics')) || [];
    for (const metric of metrics) {
      const old = sourceMap.get(metric.source_key);
      if (old && Date.parse(old.next_review_at) > now()) continue;
      const next = reviewCadence(metric, old?.cadence, old?.healthy_streak);
      checked(await db.from('enrichment_sources').upsert({ source_key: metric.source_key, cadence: next.cadence, healthy_streak: next.healthyStreak,
        metrics: metric, updated_at: iso(), next_review_at: new Date(now() + (next.cadence === 'hourly' ? 1 : 24) * 3600_000).toISOString() }));
    }
    if (config.openAiKey && now() - start < 65_000) {
      const cases = checked<any[]>(await db.rpc('pending_enrichment_evals', { worker_version: QUALITY_VERSION, batch_size: 3 })) || [];
      for (const test of cases) {
        let rank: number | null = null; let error: string | null = null; let ids: string[] = [];
        try {
          const results = await searchItems(normalizeSearchRequest({ query: test.query, limit: test.expect_in_top }), { supabaseAdmin: db, userId: test.user_id, embed: openAiEmbedder(config.openAiKey) });
          ids = results.map(r => r.id); const position = ids.indexOf(test.item_id); rank = position < 0 ? null : position + 1;
        } catch { error = 'retrieval_failed'; }
        checked(await db.from('enrichment_eval_results').upsert({ case_id: test.id, run_day: new Date(now()).toISOString().slice(0,10), quality_version: QUALITY_VERSION,
          rank, passed: error ? null : rank !== null && rank <= test.expect_in_top, error, result_ids: ids }, { onConflict: 'case_id,run_day,quality_version' }));
        counts.evaluations++;
      }
    }
    return { ...counts, quality_version: QUALITY_VERSION, repairs_enabled: config.repairsEnabled };
  } finally { checked(await db.rpc('end_enrichment_run', { token })); }
}
