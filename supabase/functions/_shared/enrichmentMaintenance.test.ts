import { describe, expect, it, vi } from 'vitest';
import { runEnrichmentMaintenance } from './enrichmentMaintenance';

async function reviewRecording(type = 'audio', transcriptStatus?: string) {
  const item = {
    id: 'saved-recording', user_id: 'owner', type, title: 'Design review',
    description: 'Recording of a design review.', page_body: null,
    file_path: 'owner/recording.m4a', attributes: { media: { transcript: { status: transcriptStatus } } },
  };
  const job = { item_id: item.id, attempts: 0, lease_token: 'lease', revision: 1, provider_state: {} };
  const attempts: Record<string, unknown>[] = [];
  const rpc = vi.fn(async (name: string) => ({ data:
    name === 'begin_enrichment_run' ? 'run-token' : name === 'claim_enrichment_jobs' ? [job] :
    name === 'reserve_enrichment_repair' ? true : ['enrichment_source_metrics', 'pending_enrichment_evals'].includes(name) ? [] : true,
  }));
  const signedUrl = vi.fn(async () => ({ data: { signedUrl: 'https://storage.example.com/recording.m4a' } }));
  const db = { rpc, storage: { from: () => ({ createSignedUrl: signedUrl }) }, from: (table: string) => {
    const value = table === 'items' ? item : table === 'enrichment_sources' ? [] : null;
    const query = {
      select: () => query, eq: () => query, update: () => query,
      maybeSingle: async () => ({ data: value }), single: async () => ({ data: value }),
      upsert: async () => ({ data: null }),
      insert: async (record: Record<string, unknown>) => { if (table === 'enrichment_attempts') attempts.push(record); return { data: null }; },
      then: (resolve: (value: unknown) => unknown) => Promise.resolve({ data: value }).then(resolve),
    };
    return query;
  } };
  const call = vi.fn(async (_name: string, _body: unknown) => ({ success: true, status: 'pending' }));
  const result = await runEnrichmentMaintenance({ db, call, now: () => 0, config: {
    repairsEnabled: true, openAiKey: 'test-only', visualEnabled: false,
    dailyRepairLimit: 10, repairsPerRun: 1, maxItems: 1,
  } });
  return { result, call, signedUrl, attempts, rpc };
}

describe('recording maintenance uses the deployed durable transcription job', () => {
  it.each(['audio', 'video'])('starts a %s job by item ID without passing a signed media URL', async type => {
    const result = await reviewRecording(type);
    expect(result.call).toHaveBeenCalledWith('transcribe-audio', { itemId: 'saved-recording' });
    expect(result.signedUrl).not.toHaveBeenCalled();
    expect(result.attempts[0]).toMatchObject({ strategy: 'transcribe-job', outcome: 'deferred' });
    expect(result.rpc.mock.calls.some(([name]) => name === 'apply_enrichment_patch')).toBe(false);
    expect(result.result).toMatchObject({ failed: 0 });
  });
  it.each(['pending', 'processing'])('does not start another job while transcript status is %s', async status => {
    const result = await reviewRecording('audio', status);
    expect(result.call.mock.calls.some(([name]) => name === 'transcribe-audio')).toBe(false);
    expect(result.signedUrl).not.toHaveBeenCalled();
    expect(result.attempts[0]).toMatchObject({ strategy: 'transcribe-job', outcome: 'deferred' });
  });
  it('does not re-transcribe a finished recording with no usable speech', async () => {
    const result = await reviewRecording('audio', 'done');
    expect(result.call.mock.calls.some(([name]) => name === 'transcribe-audio')).toBe(false);
    expect(result.signedUrl).not.toHaveBeenCalled();
    expect(result.attempts[0].reasons).toContain('transcript_unusable');
  });
  it('can resume a failed recording job through the same item-ID API', async () => {
    const result = await reviewRecording('audio', 'failed');
    expect(result.call).toHaveBeenCalledWith('transcribe-audio', { itemId: 'saved-recording' });
    expect(result.signedUrl).not.toHaveBeenCalled();
  });
});
