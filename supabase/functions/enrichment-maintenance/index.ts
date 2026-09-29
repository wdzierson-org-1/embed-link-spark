import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.7.1';
import { runEnrichmentMaintenance } from '../_shared/enrichmentMaintenance.ts';
const json = (status: number, value: unknown) => new Response(JSON.stringify(value), { status, headers: { 'Content-Type': 'application/json' } });
const bounded = (name: string, fallback: number, max: number) => Math.max(0, Math.min(max, Number(Deno.env.get(name) ?? fallback) || 0));
serve(async req => {
  if (req.method !== 'POST') return json(405, { error: 'POST only' });
  const secret = Deno.env.get('CRON_SECRET');
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  if (!(secret && req.headers.get('x-cron-secret') === secret) && !(service && req.headers.get('authorization') === `Bearer ${service}`)) return json(401, { error: 'unauthorized' });
  const url = Deno.env.get('SUPABASE_URL')!;
  const db = createClient(url, service);
  try {
    const result = await runEnrichmentMaintenance({ db, config: {
      // Start with assessment. Enable repairs after deploying the migration and provider functions together.
      repairsEnabled: Deno.env.get('ENRICHMENT_REPAIR_ENABLED') === 'true',
      openAiKey: Deno.env.get('OPENAI_API_KEY'), socialKey: Deno.env.get('SUPADATA_API_KEY'),
      visualEnabled: Deno.env.get('ENRICHMENT_VIDEO_ANALYSIS_ENABLED') === 'true',
      dailyRepairLimit: bounded('ENRICHMENT_DAILY_REPAIR_LIMIT', 100, 500),
      repairsPerRun: bounded('ENRICHMENT_REPAIRS_PER_RUN', 2, 10), maxItems: bounded('ENRICHMENT_ASSESSMENTS_PER_RUN', 100, 500),
    }, call: async (name, body) => {
      const response = await fetch(`${url}/functions/v1/${name}`, { method: 'POST', headers: { Authorization: `Bearer ${service}`, 'Content-Type': 'application/json' }, body: JSON.stringify(body), signal: AbortSignal.timeout(45_000) });
      if (!response.ok) throw new Error(`${name}_http_${response.status}`);
      return await response.json();
    } });
    return json(200, result);
  } catch (error) {
    console.error('enrichment-maintenance failed', error);
    return json(500, { error: 'Enrichment maintenance failed' });
  }
});
