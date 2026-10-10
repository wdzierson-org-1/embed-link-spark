import {
  buildObjectIntelligenceSource, objectIntelligenceFingerprint, parseObjectIntelligenceOutput, readObjectIntelligence,
  OBJECT_INTELLIGENCE_VERSION, OBJECT_INTELLIGENCE_PROMPT, OBJECT_INTELLIGENCE_OUTPUT_SCHEMA,
  type ObjectIntelligence, type ObjectIntelligenceSource,
} from './objectIntelligence.ts';
import { ENRICHMENT_COLUMNS, itemSnapshot } from './enrichmentStore.ts';
import { assessEnrichment, QUALITY_VERSION, type EnrichmentItem } from './enrichmentQuality.ts';

/** A closed extraction call: no browsing, tools, user identity, or generated summaries. */
export async function extractObjectIntelligence(apiKey: string, source: ObjectIntelligenceSource, fingerprint: string, fetcher = fetch): Promise<ObjectIntelligence> {
  const response = await fetcher('https://api.openai.com/v1/chat/completions', {
    method: 'POST', headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: 'gpt-4o-mini', temperature: 0, max_tokens: 4500,
      response_format: { type: 'json_schema', json_schema: { name: 'stash_object_intelligence', strict: true, schema: OBJECT_INTELLIGENCE_OUTPUT_SCHEMA } },
      messages: [{ role: 'system', content: OBJECT_INTELLIGENCE_PROMPT },
        { role: 'user', content: JSON.stringify({ format: source.identity.type, sources: source.sources }) }],
    }), signal: AbortSignal.timeout(30_000),
  });
  if (!response.ok) throw new Error(`object_intelligence_provider_http_${response.status}`);
  const text = await response.text();
  if (text.length > 80_000) throw new Error('extraction_response_invalid');
  const body = JSON.parse(text);
  const choice = body?.choices?.[0];
  if (choice?.finish_reason !== 'stop' || choice?.message?.refusal || typeof choice?.message?.content !== 'string') throw new Error('extraction_response_incomplete');
  const intelligence = parseObjectIntelligenceOutput(JSON.parse(choice.message.content), source, fingerprint);
  if (!intelligence) throw new Error('extraction_evidence_invalid');
  return intelligence;
}

interface Config { enabled: boolean; apiKey?: string; dailyLimit: number; hourlyLimit: number; }
interface Dependencies {
  db: any; config: Config;
  index: (item: EnrichmentItem) => Promise<{ success: boolean }>;
  extract?: typeof extractObjectIntelligence;
  now?: () => number;
}
const checked = <T>(result: { data: T; error?: unknown }): T => { if (result.error) throw new Error('database_failed'); return result.data; };

/** Independent of card completeness: source changes schedule this durable pass for every capture path. */
export async function runObjectIntelligenceWorker({ db, config, index, extract = extractObjectIntelligence, now = Date.now }: Dependencies) {
  if (!config.enabled || !config.apiKey) return { skipped: config.enabled ? 'model_unconfigured' : 'disabled' };
  const run = checked<string | null>(await db.rpc('begin_object_intelligence_run'));
  if (!run) return { skipped: 'already_running' };
  const started = now();
  const counts = { completed: 0, extracted: 0, reused: 0, deferred: 0, failed: 0, skipped: 0 };
  try {
    const jobs = checked<any[]>(await db.rpc('claim_object_intelligence_jobs', { run_token: run, batch_size: 10 })) || [];
    for (const job of jobs) {
      const jobStarted = now();
      let outcome = 'deferred'; let reason: string | null = null; let delay = 300;
      let item: EnrichmentItem | null = null; let attempted = false; let stage = 'source'; let reused = false;
      try {
        // Leave enough headroom for one model request and an index write.
        if (now() - started > 45_000) { counts.deferred++; continue; }
        item = checked<EnrichmentItem | null>(await db.from('items').select(ENRICHMENT_COLUMNS).eq('id', job.item_id).maybeSingle());
        if (!item) { outcome = 'unsupported'; continue; }
        if (item.attributes?.enrichment?.protected_fields?.object_intelligence) { outcome = 'protected'; counts.skipped++; continue; }
        const source = buildObjectIntelligenceSource(item);
        if (!source) { outcome = 'no_evidence'; counts.skipped++; continue; }
        const fingerprint = await objectIntelligenceFingerprint(source);
        let intelligence = readObjectIntelligence(item.attributes?.object_intelligence, source, fingerprint);
        reused = !!intelligence;
        if (!intelligence) {
          if (job.attempts >= 3) { outcome = 'failed'; reason = 'attempts_exhausted'; counts.failed++; continue; }
          const reserved = checked<boolean>(await db.rpc('reserve_object_intelligence_call', {
            run_token: run, target_id: item.id, token: job.lease_token, daily_limit: config.dailyLimit, hourly_limit: config.hourlyLimit,
          }));
          if (!reserved) { counts.deferred++; continue; }
          attempted = true; stage = 'extraction';
          intelligence = await extract(config.apiKey, source, fingerprint);
          stage = 'persistence';
          const committed = checked<boolean>(await db.rpc('commit_object_intelligence', {
            target_id: item.id, token: job.lease_token, expected: itemSnapshot(item), intelligence,
          }));
          if (!committed) { reason = 'item_changed'; counts.deferred++; continue; }
          counts.extracted++;
          item = checked<EnrichmentItem | null>(await db.from('items').select(ENRICHMENT_COLUMNS).eq('id', job.item_id).maybeSingle());
          if (!item) { outcome = 'unsupported'; continue; }
          // A source edit between commit and refetch belongs to the new queue revision.
          const current = buildObjectIntelligenceSource(item);
          if (!current || await objectIntelligenceFingerprint(current) !== fingerprint) { reason = 'item_changed'; counts.deferred++; continue; }
        } else counts.reused++;
        attempted = true; stage = 'index';
        if (!(await index(item)).success) throw new Error('index_update_failed');
        outcome = 'complete'; counts.completed++;
      } catch (error) {
        // Never retain provider bodies, private source text, signed URLs, or credentials in diagnostics.
        reason = stage === 'extraction' ? 'object_intelligence_extraction_failed' : stage === 'index' ? 'object_intelligence_index_failed' : 'object_intelligence_persistence_failed';
        if (stage === 'extraction' && error instanceof Error && /^object_intelligence_provider_http_[1-5][0-9]{2}$/.test(error.message)) reason = error.message;
        outcome = 'retry'; delay = 3600; counts.failed++;
      } finally {
        try {
          if (item && attempted) {
            checked(await db.from('enrichment_attempts').insert({ item_id: item.id, user_id: item.user_id,
              source_key: assessEnrichment(item).source_key, quality_version: QUALITY_VERSION, strategy: OBJECT_INTELLIGENCE_VERSION,
              outcome: outcome === 'complete' ? reused ? 'unchanged' : 'improved' : outcome === 'retry' ? 'failed' : 'deferred',
              reasons: reason ? [reason] : [], elapsed_ms: Math.max(0, now() - jobStarted),
            }));
          }
        } finally {
          checked(await db.rpc('finish_object_intelligence_job', { target_id: job.item_id, token: job.lease_token,
            expected_revision: job.revision, outcome, delay_seconds: delay, failure_code: reason }));
        }
      }
    }
    return counts;
  } finally { checked(await db.rpc('end_object_intelligence_run', { token: run })); }
}
